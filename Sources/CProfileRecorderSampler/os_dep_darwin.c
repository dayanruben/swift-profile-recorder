//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if __APPLE__

#include <pthread.h>
#include <mach/mach.h>
#include <mach/thread_info.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <stdio.h>

#include "os_dep.h"
#include "interface.h"
#include "asserts.h"

struct thread_info *swipr_os_dep_create_thread_list(size_t *all_threads_count) {
    thread_array_t threads = NULL;
    mach_msg_type_number_t flavor = THREAD_IDENTIFIER_INFO_COUNT;
    mach_msg_type_number_t threads_count = 0;
    kern_return_t kret = task_threads(mach_task_self(),
                                     &threads,
                                     &threads_count);
    if (kret) {
        *all_threads_count = 0;
        return NULL;
    }
    *all_threads_count = (size_t) threads_count;
    struct thread_info *all_threads = calloc(SWIPR_MAX_MUTATOR_THREADS, sizeof(struct thread_info));
    if (!all_threads) {
        return NULL;
    }
    memset(all_threads, 0, sizeof(*all_threads) * SWIPR_MAX_MUTATOR_THREADS);

    for (int i = 0; i < threads_count; i++) {
        pthread_t pthread = pthread_from_mach_thread_np(threads[i]);
        if (pthread == NULL || threads[i] == mach_thread_self()) {
            // skip controller and mach threads without corresponding pthreads
            // set ti_id to 0 so they will be ignored
            all_threads[i].ti_id = 0;
            *all_threads_count--;
            continue;
        }
        char name[32] = {0};
        int getname_ret = pthread_getname_np(pthread, name, sizeof(name));
        
        // ignore threads for which we can't get mach info
        thread_identifier_info_data_t tid_info = {0};
        kern_return_t info_ret = thread_info(threads[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&tid_info, &flavor);
        if (info_ret != KERN_SUCCESS) {
            UNSAFE_DEBUG("failed to get thread_info in create thread list for mach port %llu | %llx\n", threads[i], threads[i]);
            all_threads[i].ti_id = 0;
            *all_threads_count--;
            continue;
        }

        all_threads[i].ti_id = tid_info.thread_id;
        all_threads[i].ti_os_specific.mach_thread = threads[i];
        if (name[0] == 0) {
            strcpy(all_threads[i].ti_name, "<n/a>"); // threads may have empty names
        } else {
            _Static_assert(sizeof(all_threads[0].ti_name) >= sizeof(name), "destination too small for memcpy");
            memcpy(all_threads[i].ti_name, name, sizeof(all_threads[i].ti_name));
        }
    }
    kret = vm_deallocate(mach_task_self(),
                         (vm_address_t)threads,
                         threads_count * sizeof(thread_t));

    swipr_precondition(kret == KERN_SUCCESS);
    swipr_precondition(all_threads_count >= 0);
    return all_threads;
}

int swipr_os_dep_destroy_thread_list(struct thread_info *thread_list) {
    swipr_precondition(thread_list);
    for (int i = 0; i < SWIPR_MAX_MUTATOR_THREADS; i++) {
        if (thread_list[i].ti_os_specific.mach_thread == THREAD_NULL) {
            // Note that ti_id == 0 doesn't mean it wasn't allocated a port right
            // E.g. thread might die in swipr_make_sample, where its id will be set to 0
            // but we still allocated a port right in create_thread_listtgat needs to be deallocated
            continue;
        } else {
            kern_return_t kret = mach_port_deallocate(mach_task_self(), thread_list[i].ti_os_specific.mach_thread);
            swipr_precondition(kret == KERN_SUCCESS || kret == KERN_TERMINATED);
        }
    }
    free(thread_list);
    return 0;
}

int swipr_os_dep_list_all_dynamic_libs(struct swipr_dynamic_lib *all_libs,
                                       size_t all_libs_capacity,
                                       size_t *all_libs_count) {
    int img_count = _dyld_image_count();
    int libs_count = 0;
    for (int i = 0; i < img_count; i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        intptr_t slide             = _dyld_get_image_vmaddr_slide(i);
        const char *name           = _dyld_get_image_name(i);

        // Move ptr over mach header, offset depends on header size
        bool is64 = (header->magic == MH_MAGIC_64 || header->magic == MH_CIGAM_64);
        const uint8_t *ld_cmd_ptr = (const uint8_t *)header
                              + (is64 ? sizeof(struct mach_header_64)
                                     : sizeof(struct mach_header));

        // we iterate over load commands and finds __TEXT segments.
        // Note: vmaddr is the intended load address of the Mach-O binary, 
        // it is adjusted by the ASLR slide to give the runtime address
        for (int i = 0; i < header->ncmds; i++) {
            const struct load_command *ld_cmd = (const struct load_command *)ld_cmd_ptr;
            
            if (ld_cmd->cmd == LC_SEGMENT) {
                const struct segment_command *seg = (const struct segment_command *)ld_cmd;
                if (strcmp(seg->segname, "__TEXT") == 0) {
                    uintptr_t start = seg->vmaddr + slide;
                    uintptr_t end   = start + seg->vmsize;
                    
                    memcpy(all_libs[libs_count].dl_name, name, sizeof(all_libs[libs_count].dl_name));
                    all_libs[libs_count].dl_name[sizeof(all_libs[libs_count].dl_name) - 1] = 0; //truncates string
                    all_libs[libs_count].dl_file_mapped_at = slide;
                    all_libs[libs_count].dl_seg_start_addr = start;
                    all_libs[libs_count].dl_seg_end_addr = end;
                    libs_count++;
                }
            }
            else if (ld_cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)ld_cmd;
                if (strcmp(seg->segname, "__TEXT") == 0) {
                    uintptr_t start = seg->vmaddr + slide;
                    uintptr_t end   = start + seg->vmsize;
                    
                    memcpy(all_libs[libs_count].dl_name, name, sizeof(all_libs[libs_count].dl_name));
                    all_libs[libs_count].dl_name[sizeof(all_libs[libs_count].dl_name) - 1] = 0; //truncates string
                    all_libs[libs_count].dl_file_mapped_at = slide;
                    all_libs[libs_count].dl_seg_start_addr = start;
                    all_libs[libs_count].dl_seg_end_addr = end;
                    libs_count++;
                }
            }
            ld_cmd_ptr += ld_cmd->cmdsize;
        }
    }
    swipr_precondition(libs_count <= all_libs_capacity);
    *all_libs_count = libs_count;
    return 0;
}

int swipr_os_dep_set_current_thread_name(const char *name) {
    if (pthread_setname_np(name)){
        return -1;
    }
    return 0;
}

int swipr_os_dep_get_current_thread_name(char *name, size_t len) {
    if (pthread_getname_np(pthread_self(), name, len)){
        return -1;
    }
    return 0;
}

#endif

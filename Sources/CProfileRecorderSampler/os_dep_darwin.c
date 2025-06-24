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
#include <mach/thread_act.h>
#include <mach/thread_info.h>
#include "interface.h"
#include "os_dep.h"
#include <string.h>
#include "asserts.h"

int swipr_os_dep_list_all_threads(struct thread_info *all_threads,
                                  size_t all_threads_capacity,
                                  size_t *all_threads_count) {
    thread_array_t threads = NULL;
    mach_msg_type_number_t threads_count = 0;
    kern_return_t kret = task_threads(mach_task_self(),
                                     &threads,
                                     &threads_count);
    if (kret) {
        *all_threads_count = 0;
        return -1;
    }

    *all_threads_count = (size_t) threads_count;
    mach_msg_type_number_t flavor = THREAD_IDENTIFIER_INFO_COUNT;
    
    for (mach_msg_type_number_t i = 0; i < threads_count; i++) {
        pthread_t pthread = pthread_from_mach_thread_np(threads[i]);
        swipr_precondition(pthread);
        char name[32] = {0};
        int getname_ret = pthread_getname_np(pthread, name, sizeof(name));
        
        thread_identifier_info_data_t tid_info;
        kern_return_t info_ret = thread_info(threads[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&tid_info, &flavor);
        swipr_precondition(getname_ret == 0);

        all_threads[i].ti_id = tid_info.thread_id;
        if (name[0] == 0) {
            strcpy(all_threads[i].ti_name, "<n/a>"); // some thread may have empty name
        } else {
            _Static_assert(sizeof(all_threads[0].ti_name) >= sizeof(name), "destination not large enough");
            memcpy(all_threads[i].ti_name, name, sizeof(all_threads[i].ti_name));
        }
    }

    // After careful analysis and examples from high profile codebases
    // we decided to include this block to clean up port rights and memory
    for (mach_msg_type_number_t i = 0; i < threads_count; i++) {
        kret = mach_port_deallocate(mach_task_self(), threads[i]);
        swipr_precondition(kret == KERN_SUCCESS);
    }
    kret = vm_deallocate(mach_task_self(),
                       (vm_address_t)threads,
                        threads_count * sizeof(thread_act_t));

    swipr_precondition (kret == KERN_SUCCESS);
    return 0;
}

int swipr_os_dep_list_all_dynamic_libs(struct swipr_dynamic_lib *all_libs,
                                       size_t all_libs_capacity,
                                       size_t *all_libs_count) {
    *all_libs_count = 0;
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

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

#if __linux__

#define _GNU_SOURCE
#include <dirent.h>
#include <sys/errno.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <link.h>
#include <string.h>
#include <fcntl.h>

#include "os_dep.h"
#include "interface.h"
#include "common.h"

struct thread_info *swipr_os_dep_create_thread_list(size_t *all_threads_count) {
    struct thread_info *all_threads = calloc(sizeof(struct thread_info), SWIPR_MAX_MUTATOR_THREADS);
    if (!all_threads) {
        return NULL;
    }
    DIR *dir = opendir("/proc/self/task");
    if (!dir) {
        goto error;
    }
    int next_index = 0;
    pid_t my_tid = swipr_os_dep_get_thread_id();
    
    struct dirent *ent = NULL;
    while (true) {
        errno = 0;
        ent = readdir(dir);
        if (ent == NULL) {
            switch (errno) {
                case 0:
                    goto out;
                case EINTR:
                    continue;
                default:
                    goto error;
            }
            if (errno == EINTR) {
                continue;
            }
        }
        
        pid_t tid = atol(ent->d_name);
        if (tid != 0 && tid != my_tid) {
            int idx = next_index++;
            all_threads[idx].ti_id = tid;
            char file_path[128] = {0};
            snprintf(file_path, 128, "/proc/self/task/%d/comm", tid);
            int fd = open(file_path, O_RDONLY);
            if (fd >= 0) {
                int how_much = read(fd, all_threads[idx].ti_name, 32);
                all_threads[idx].ti_name[how_much > 0 ? how_much-1 : 0] = 0; // get rid of the \n
                int ret = close(fd);
                // continue if close successful or failed due to interrupt
                if (!(ret == 0 || (ret == -1 && errno == EINTR))) {
                    goto error;
                }
            }
        }
    }
    
out:
    closedir(dir);
    *all_threads_count = next_index;
    return all_threads;
error:
    closedir(dir);
    swipr_os_dep_destroy_thread_list(all_threads);
    *all_threads_count = 0;
    return NULL;
}

int swipr_os_dep_destroy_thread_list(struct thread_info *thread_list) {
    swipr_precondition(thread_list);
    free(thread_list);
    return 0;
}

struct dl_iterate_phdr_data {
    struct swipr_dynamic_lib *dli_all_libs;
    size_t dli_all_libs_capacity;
    size_t dli_all_libs_count;
    bool dli_first;
};

static int
dl_iterate_phdr_cb(struct dl_phdr_info *info, size_t size, void *v_data) {
    struct dl_iterate_phdr_data *data = (typeof(data))v_data;

    for (int i=0; i<info->dlpi_phnum; i++) {
        const ElfW(Phdr) *phdr = &info->dlpi_phdr[i];
        if (phdr->p_type != PT_LOAD) {
            continue;
        }

        struct swipr_dynamic_lib *my_lib = &data->dli_all_libs[data->dli_all_libs_count++];
        if (data->dli_first) {
            readlink("/proc/self/exe", my_lib->dl_name, sizeof(my_lib->dl_name));
        } else {
            strncpy(my_lib->dl_name, info->dlpi_name, sizeof(my_lib->dl_name));
        }
        my_lib->dl_name[sizeof(my_lib->dl_name) - 1] = 0;

        my_lib->dl_file_mapped_at = info->dlpi_addr;
        my_lib->dl_seg_start_addr = info->dlpi_addr + phdr->p_vaddr;
        my_lib->dl_seg_end_addr = info->dlpi_addr + phdr->p_vaddr + phdr->p_memsz;
    }
    data->dli_first = false;

    return 0;
}

int swipr_os_dep_list_all_dynamic_libs(struct swipr_dynamic_lib *all_libs,
                                 size_t all_libs_capacity,
                                 size_t *all_libs_count) {
    struct dl_iterate_phdr_data data = {
        .dli_all_libs = all_libs,
        .dli_all_libs_capacity = all_libs_capacity,
        .dli_all_libs_count = 0,
        .dli_first = true,
    };
    size_t next = 0;
    int err = dl_iterate_phdr(dl_iterate_phdr_cb, &data);
    *all_libs_count = data.dli_all_libs_count;

    return err;
}

int swipr_os_dep_set_current_thread_name(const char *name) {
    return pthread_setname_np(pthread_self(), name);
}

int swipr_os_dep_get_current_thread_name(char *name, size_t len) {
#ifdef __ANDROID__
    if (len < 16) {
        return -1;
    }
    return TEMP_FAILURE_RETRY(prctl(PR_GET_NAME, name)) == -1 ? -1 : 0;
#else
    return pthread_getname_np(pthread_self(), name, len);
#endif
}

#endif

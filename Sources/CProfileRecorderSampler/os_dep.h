//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2022-2025 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
#ifndef swipr_os_dep_h
#define swipr_os_dep_h

struct thread_info;

#if __APPLE__ && __has_include(<dispatch/dispatch.h>)
#  include "os_dep_dispatch.h"
#elif __has_include(<pthread.h>)
#  include "os_dep_pthread.h"
#else
#  error "unsupported threading libs"
#endif

#if __linux__
#  include "os_dep_linux.h"
#elif __APPLE__
#  include "os_dep_darwin.h"
#else
#  error "unsupported OS"
#endif

int swipr_os_dep_list_all_threads(struct thread_info *all_threads,
                            size_t all_threads_capacity,
                            size_t *all_threads_count);

struct swipr_dynamic_lib {
    char dl_name[1024];
    uintptr_t dl_file_mapped_at;
    uintptr_t dl_seg_start_addr;
    uintptr_t dl_seg_end_addr;
};

int swipr_os_dep_list_all_dynamic_libs(struct swipr_dynamic_lib *all_libs,
                                 size_t all_libs_capacity,
                                 size_t *all_libs_count);

#endif /* swipr_os_dep_h */

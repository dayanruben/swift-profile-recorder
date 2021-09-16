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
#if __APPLE__

#include <pthread.h>
#include "os_dep.h"

extern pthread_t target; // remove

int os_dep_list_all_threads(os_dep_thread_id *all_threads,
                            size_t all_threads_capacity,
                            size_t *all_threads_count) {
    all_threads[0] = target;
    *all_threads_count = 1;
}

int os_dep_list_all_dynamic_libs(struct cspl_dynamic_lib *all_libs,
                                 size_t all_libs_capacity,
                                 size_t *all_libs_count) {
    *all_libs_count = 0;
}
#endif

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
//
//  Header.h
//  Header
//
//  Created by Johannes Weiss on 15/09/2021.
//

#ifndef swipr_os_dep_macos_h
#define swipr_os_dep_macos_h

#ifndef __APPLE__
# error "This is only meant to be included on Darwin."
#endif

#include <dispatch/dispatch.h>
#include "os_dep_darwin.h"

typedef dispatch_semaphore_t swipr_os_dep_sem;
#define swipr_os_dep_sem_create dispatch_semaphore_create
#define swipr_os_dep_sem_free dispatch_release
#define swipr_os_dep_sem_signal dispatch_semaphore_signal
#define swipr_os_dep_deadline dispatch_time_t

static inline swipr_os_dep_deadline
swipr_os_dep_create_deadline(void) {
    return dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC);
}

static inline void
swipr_os_dep_sem_wait(swipr_os_dep_sem sem) {
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

static inline int
swipr_os_dep_sem_wait_with_deadline(swipr_os_dep_sem sem, swipr_os_dep_deadline deadline) {
    return dispatch_semaphore_wait(sem, deadline);
}

static inline swipr_os_dep_thread_id
swipr_os_dep_get_thread_id(void) {
    return pthread_self();
}

#endif /* swipr_os_dep_macos_h */

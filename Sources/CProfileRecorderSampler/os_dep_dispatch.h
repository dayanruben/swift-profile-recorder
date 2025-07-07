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

#ifndef swipr_os_dep_macos_h
#define swipr_os_dep_macos_h

#ifndef __APPLE__
# error "This is only meant to be included on Darwin."
#endif

#include <dispatch/dispatch.h>
#include "os_dep_darwin.h"
#include "asserts.h"

typedef dispatch_semaphore_t swipr_os_dep_sem;
#define swipr_os_dep_sem_create dispatch_semaphore_create
#define swipr_os_dep_sem_free dispatch_release
#define swipr_os_dep_sem_signal dispatch_semaphore_signal
#define swipr_os_dep_deadline dispatch_time_t

static inline swipr_os_dep_deadline
swipr_os_dep_create_deadline(uint64_t nsecs) {
    return dispatch_time(DISPATCH_TIME_NOW, nsecs);
}

static inline void
swipr_os_dep_sem_wait(swipr_os_dep_sem sem) {
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

static inline int
swipr_os_dep_sem_wait_with_deadline(swipr_os_dep_sem sem, swipr_os_dep_deadline deadline) {
    return (int)dispatch_semaphore_wait(sem, deadline);
}

static inline swipr_os_dep_thread_id
swipr_os_dep_get_thread_id(void) {
    thread_identifier_info_data_t tid_info;
    mach_msg_type_number_t flavor = THREAD_IDENTIFIER_INFO_COUNT;
    
    kern_return_t kret = thread_info(mach_thread_self(),
                                     THREAD_IDENTIFIER_INFO,
                                     (thread_info_t)&tid_info,
                                     &flavor);
    swipr_precondition(kret == KERN_SUCCESS);
    return tid_info.thread_id;
}

#endif /* swipr_os_dep_macos_h */

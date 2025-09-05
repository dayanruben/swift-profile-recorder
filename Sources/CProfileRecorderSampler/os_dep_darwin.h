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

#ifndef swipr_os_dep_dawin_h
#define swipr_os_dep_dawin_h

#import <pthread.h>
#include <mach/mach.h>

typedef intptr_t swipr_os_dep_thread_id;

static inline int swipr_os_dep_kill(swipr_os_dep_thread_id thread_id, int signal) {
    return pthread_kill((pthread_t)thread_id, signal);
}

#endif /* swipr_os_dep_dawin_h */

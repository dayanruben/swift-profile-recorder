//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift Profile Recorder project authors
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

#define swipr_os_dep_thread_id pthread_t
#define swipr_os_dep_kill pthread_kill

#endif /* swipr_os_dep_dawin_h */

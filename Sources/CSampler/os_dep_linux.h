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

#ifndef os_dep_linux_h
#define os_dep_linux_h

#define _GNU_SOURCE
#include <unistd.h>
#include <signal.h>           /* Definition of SIG* constants */
#include <sys/syscall.h>      /* Definition of SYS_* constants */

#define os_dep_thread_id pid_t
#define os_dep_get_thread_id gettid
static inline int os_dep_kill(os_dep_thread_id tid, sig_t sig) {
    return syscall(SYS_tkill, tid, sig);
}

#endif /* os_dep_linux_h */

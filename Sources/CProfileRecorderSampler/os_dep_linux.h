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

#ifndef swipr_os_dep_linux_h
#define swipr_os_dep_linux_h

#define _GNU_SOURCE
#include <unistd.h>
#include <signal.h>           /* Definition of SIG* constants */
#include <sys/syscall.h>      /* Definition of SYS_* constants */

#define swipr_os_dep_thread_id pid_t

static inline pid_t
swipr_os_dep_get_thread_id(void) {
    return syscall(SYS_gettid);
}

static inline int swipr_os_dep_kill(swipr_os_dep_thread_id tid, int sig) {
    return syscall(SYS_tgkill, getpid(), tid, sig);
}

#endif /* swipr_os_dep_linux_h */

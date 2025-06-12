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


#ifndef common_h
#define common_h

#include <string.h>
#include <stdio.h>
#include <unistd.h>

#define SWIPR_MAX_MUTATOR_THREADS 1024
#define SWIPR_MAX_STACK_DEPTH 128

#define SWIPR_NSEC_PER_USEC 1000ULL
#define SWIPR_NSEC_PER_MSEC (1000ULL * SWIPR_NSEC_PER_USEC)
#define SWIPR_NSEC_PER_SEC (1000ULL * SWIPR_NSEC_PER_MSEC)

#if defined(SWIPR_ENABLE_UNSAFE_DEBUG)
#  define UNSAFE_DEBUG(...) \
    do { \
        char buffer[512] = {0}; \
        snprintf(buffer, sizeof(buffer), "ProfileRecorder: " __VA_ARGS__); \
        write(STDERR_FILENO, buffer, strlen(buffer)); \
    } while (0)
#else
#  define UNSAFE_DEBUG(...) do { } while (0)
#endif

#endif /* common_h */

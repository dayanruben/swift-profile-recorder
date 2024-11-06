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

#ifndef asserts_h
#define asserts_h

#include <stdlib.h>

#define swipr_precondition(_x) do { \
    if (!(_x)) { \
        char buffer[128] = { 0 }; \
        snprintf(buffer, sizeof(buffer), "ProfileRecorder precondition failed: %s:%d: " #_x "\n", __FILE__, __LINE__); \
        write(STDERR_FILENO, buffer, strlen(buffer)); \
        abort(); \
    } \
} while(0)

#endif /* asserts_h */

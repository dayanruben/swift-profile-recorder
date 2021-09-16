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
#ifndef CSampler_h
#define CSampler_h

#include <pthread.h> // remove
#if __linux__
#include <bits/pthreadtypes.h> // remove
#endif

int cspl_request_sample(void);
int cspl_initialize(void);

extern pthread_t target;

#endif /* CSampler_h */

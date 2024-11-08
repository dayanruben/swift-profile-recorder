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

#ifndef CSampler_h
#define CSampler_h

#include <unistd.h>
#include <stdio.h>

int swipr_request_sample(FILE *output,
                         size_t sample_count,
                         useconds_t usecs_between_samples);
int swipr_initialize(void);

#endif /* CSampler_h */

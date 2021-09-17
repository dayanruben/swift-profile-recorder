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

#ifndef asserts_h
#define asserts_h

#include <stdlib.h>

#define swipr_precondition(_x) do { if (!(_x)) { abort(); } } while(0)

#endif /* asserts_h */

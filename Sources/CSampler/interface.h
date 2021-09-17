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

#ifndef interface_h
#define interface_h

#include "os_dep.h"
#include "../CLibUnwind/include/CLibUnwind.h"

#define CSPL_MAX_MUTATOR_THREADS 1024
#define CSPL_MAX_STACK_DEPTH 128

enum cspl_c2ms_state {
    cspl_c2m_idle = 0,
    cspl_c2m_preparing = 1,
    cspl_c2m_sampling = 2,
    cspl_c2m_processing = 3,
};

struct collector_to_mutator {
    os_dep_thread_id c2m_thread_id;
    os_dep_sem c2m_proceed;
    os_dep_sem m2c_proceed;
    swift_unwind_unw_context_t c2m_context;
};

struct collector_to_mutators {
    _Atomic enum cspl_c2ms_state c2ms_state;
    struct collector_to_mutator c2ms_c2ms[CSPL_MAX_MUTATOR_THREADS];
};

struct thread_info {
    os_dep_thread_id ti_id;
    char ti_name[32];
};

#endif /* interface_h */

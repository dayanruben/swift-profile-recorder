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

#ifndef interface_h
#define interface_h

#include "common.h"
#include "os_dep.h"
#include "fp_unwinder.h"
// FIXME: Proper import.
#include "../CProfileRecorderLibUnwind/include/CProfileRecorderLibUnwind.h"

enum swipr_c2ms_state {
    swipr_c2m_idle = 0,
    swipr_c2m_preparing = 1,
    swipr_c2m_sampling = 2,
    swipr_c2m_processing = 3,
};

struct collector_to_mutator {
    swipr_os_dep_thread_id c2m_thread_id;
    swipr_os_dep_sem c2m_proceed;
    swipr_os_dep_sem m2c_proceed;
    swipr_unw_context_t c2m_context;
    struct swipr_fp_unwinder_context c2m_tiny_context;
};

struct collector_to_mutators {
    _Atomic enum swipr_c2ms_state c2ms_state;
    struct collector_to_mutator c2ms_c2ms[SWIPR_MAX_MUTATOR_THREADS];
};

struct thread_info {
    swipr_os_dep_thread_id ti_id;
    char ti_name[32];
};

#endif /* interface_h */

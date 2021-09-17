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
//===------------------------- Unwind-EHABI.hpp ---------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//
//===----------------------------------------------------------------------===//

#ifndef __UNWIND_EHABI_H__
#define __UNWIND_EHABI_H__

#include <__libunwind_config.h>

#if defined(_LIBUNWIND_ARM_EHABI)

#include <stdint.h>
#include <unwind.h>

// Unable to unwind in the ARM index table (section 5 EHABI).
#define UNW_EXIDX_CANTUNWIND 0x1

static inline uint32_t signExtendPrel31(uint32_t data) {
  return data | ((data & 0x40000000u) << 1);
}

static inline uint32_t readPrel31(const uint32_t *data) {
  return (((uint32_t)(uintptr_t)data) + signExtendPrel31(*data));
}

#if defined(__cplusplus)
extern "C" {
#endif

extern _swipr_Unwind_Reason_Code __aeabi_unwind_cpp_pr0(
    _swipr_Unwind_State state, _swipr_Unwind_Control_Block *ucbp, _swipr_Unwind_Context *context);

extern _swipr_Unwind_Reason_Code __aeabi_unwind_cpp_pr1(
    _swipr_Unwind_State state, _swipr_Unwind_Control_Block *ucbp, _swipr_Unwind_Context *context);

extern _swipr_Unwind_Reason_Code __aeabi_unwind_cpp_pr2(
    _swipr_Unwind_State state, _swipr_Unwind_Control_Block *ucbp, _swipr_Unwind_Context *context);

#if defined(__cplusplus)
} // extern "C"
#endif

#endif // defined(_LIBUNWIND_ARM_EHABI)

#endif  // __UNWIND_EHABI_H__

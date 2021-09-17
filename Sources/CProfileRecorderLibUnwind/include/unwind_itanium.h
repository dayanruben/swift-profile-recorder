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
//===------------------------------- unwind.h -----------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//
// C++ ABI Level 1 ABI documented at:
//   https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html
//
//===----------------------------------------------------------------------===//

#ifndef __ITANIUM_UNWIND_H__
#define __ITANIUM_UNWIND_H__

struct _swift_unwind_Unwind_Context;   // opaque
struct _swift_unwind_Unwind_Exception; // forward declaration
typedef struct _swift_unwind_Unwind_Exception _swift_unwind_Unwind_Exception;
typedef uint64_t _swift_unwind_Unwind_Exception_Class;

struct _swift_unwind_Unwind_Exception {
  _swift_unwind_Unwind_Exception_Class exception_class;
  void (*exception_cleanup)(_swift_unwind_Unwind_Reason_Code reason,
                            _swift_unwind_Unwind_Exception *exc);
#if defined(__SEH__) && !defined(__USING_SJLJ_EXCEPTIONS__)
  uintptr_t private_[6];
#else
  uintptr_t private_1; // non-zero means forced unwind
  uintptr_t private_2; // holds sp that phase1 found for phase2 to use
#endif
#if __SIZEOF_POINTER__ == 4
  // The implementation of _swift_unwind_Unwind_Exception uses an attribute mode on the
  // above fields which has the side effect of causing this whole struct to
  // round up to 32 bytes in size (48 with SEH). To be more explicit, we add
  // pad fields added for binary compatibility.
  uint32_t reserved[3];
#endif
  // The Itanium ABI requires that _swift_unwind_Unwind_Exception objects are "double-word
  // aligned".  GCC has interpreted this to mean "use the maximum useful
  // alignment for the target"; so do we.
} __attribute__((__aligned__));

typedef _swift_unwind_Unwind_Reason_Code (*_swift_unwind_Unwind_Personality_Fn)(
    int version, _swift_unwind_Unwind_Action actions, uint64_t exceptionClass,
    _swift_unwind_Unwind_Exception *exceptionObject, struct _swift_unwind_Unwind_Context *context);

#ifdef __cplusplus
extern "C" {
#endif

//
// The following are the base functions documented by the C++ ABI
//
#ifdef __USING_SJLJ_EXCEPTIONS__
extern _swift_unwind_Unwind_Reason_Code
    _swift_unwind_Unwind_SjLj_RaiseException(_swift_unwind_Unwind_Exception *exception_object);
extern void _swift_unwind_Unwind_SjLj_Resume(_swift_unwind_Unwind_Exception *exception_object);
#else
extern _swift_unwind_Unwind_Reason_Code
    _swift_unwind_Unwind_RaiseException(_swift_unwind_Unwind_Exception *exception_object);
extern void _swift_unwind_Unwind_Resume(_swift_unwind_Unwind_Exception *exception_object);
#endif
extern void _swift_unwind_Unwind_DeleteException(_swift_unwind_Unwind_Exception *exception_object);


extern uintptr_t _swift_unwind_Unwind_GetGR(struct _swift_unwind_Unwind_Context *context, int index);
extern void _swift_unwind_Unwind_SetGR(struct _swift_unwind_Unwind_Context *context, int index,
                          uintptr_t new_value);
extern uintptr_t _swift_unwind_Unwind_GetIP(struct _swift_unwind_Unwind_Context *context);
extern void _swift_unwind_Unwind_SetIP(struct _swift_unwind_Unwind_Context *, uintptr_t new_value);

#ifdef __cplusplus
}
#endif

#endif // __ITANIUM_UNWIND_H__

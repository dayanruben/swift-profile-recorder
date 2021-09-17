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
//===------------------------ libunwind_ext.h -----------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//
//  Extensions to libunwind API.
//
//===----------------------------------------------------------------------===//

#ifndef __LIBUNWIND_EXT__
#define __LIBUNWIND_EXT__

#include "config.h"
#include <libunwind.h>
#include <unwind.h>

#define UNW_STEP_SUCCESS 1
#define UNW_STEP_END     0

#ifdef __cplusplus
extern "C" {
#endif

extern int __swift_unwind_unw_getcontext(swift_unwind_unw_context_t *);
extern int __swift_unwind_unw_init_local(swift_unwind_unw_cursor_t *, swift_unwind_unw_context_t *);
extern int __swift_unwind_unw_step(swift_unwind_unw_cursor_t *);
extern int __swift_unwind_unw_get_reg(swift_unwind_unw_cursor_t *, swift_unwind_unw_regnum_t, swift_unwind_unw_word_t *);
extern int __swift_unwind_unw_get_fpreg(swift_unwind_unw_cursor_t *, swift_unwind_unw_regnum_t, swift_unwind_unw_fpreg_t *);
extern int __swift_unwind_unw_set_reg(swift_unwind_unw_cursor_t *, swift_unwind_unw_regnum_t, swift_unwind_unw_word_t);
extern int __swift_unwind_unw_set_fpreg(swift_unwind_unw_cursor_t *, swift_unwind_unw_regnum_t, swift_unwind_unw_fpreg_t);
extern int __swift_unwind_unw_resume(swift_unwind_unw_cursor_t *);

#ifdef __arm__
/* Save VFP registers in FSTMX format (instead of FSTMD). */
extern void __swift_unwind_unw_save_vfp_as_X(swift_unwind_unw_cursor_t *);
#endif

extern const char *__swift_unwind_unw_regname(swift_unwind_unw_cursor_t *, swift_unwind_unw_regnum_t);
extern int __swift_unwind_unw_get_proc_info(swift_unwind_unw_cursor_t *, swift_unwind_unw_proc_info_t *);
extern int __swift_unwind_unw_is_fpreg(swift_unwind_unw_cursor_t *, swift_unwind_unw_regnum_t);
extern int __swift_unwind_unw_is_signal_frame(swift_unwind_unw_cursor_t *);
extern int __swift_unwind_unw_get_proc_name(swift_unwind_unw_cursor_t *, char *, size_t, swift_unwind_unw_word_t *);

// SPI
extern void __swift_unwind_unw_iterate_dwarf_unwind_cache(void (*func)(
    swift_unwind_unw_word_t ip_start, swift_unwind_unw_word_t ip_end, swift_unwind_unw_word_t fde, swift_unwind_unw_word_t mh));

// IPI
extern void __swift_unwind_unw_add_dynamic_fde(swift_unwind_unw_word_t fde);
extern void __swift_unwind_unw_remove_dynamic_fde(swift_unwind_unw_word_t fde);

#if defined(_LIBUNWIND_ARM_EHABI)
extern const uint32_t* decode_eht_entry(const uint32_t*, size_t*, size_t*);
extern _swift_unwind_Unwind_Reason_Code _swift_unwind_Unwind_VRS_Interpret(_swift_unwind_Unwind_Context *context,
                                                 const uint32_t *data,
                                                 size_t offset, size_t len);
#endif

#ifdef __cplusplus
}
#endif

#endif // __LIBUNWIND_EXT__

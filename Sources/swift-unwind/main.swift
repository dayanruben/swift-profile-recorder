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
@_implementationOnly import CLibUnwind
import Dispatch
import AppKit

@inline(never)
func doit(_ n: Int) {
    guard n > 0 else {
        var context = swift_unwind_unw_context_t()
        let ret = swift_unwind_unw_getcontext(&context)
        print("getcontext", ret)
        
        let g = DispatchGroup()
        
        DispatchQueue.global().async(group: g, qos: .default, flags: .detached) { [context] in
            var cursor = swift_unwind_unw_cursor_t()

            var context = context
            //let r = swift_unwind_unw_getcontext(&context)
            var ret = swift_unwind_unw_init_local(&cursor, &context)
            print("init local", ret)

            repeat {
                var word = swift_unwind_unw_word_t()
                ret = swift_unwind_unw_get_reg(&cursor, swift_unwind_unw_regnum_t(UNW_REG_IP), &word)
                print("get reg IP", ret, word)
                
                ret = swift_unwind_unw_get_reg(&cursor, swift_unwind_unw_regnum_t(UNW_REG_SP), &word)
                print("get reg SP", ret, word)

                ret = swift_unwind_unw_step(&cursor)
                print("step", ret, word)
            } while ret == 1
            print(ret)

        }
        g.wait()
        return
    }
    doit(n - 1)
}

doit(100)
print("DONE")

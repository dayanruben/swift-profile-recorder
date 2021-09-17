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
@_implementationOnly import CSampler
@_implementationOnly import CLibUnwind
import NIO

import Dispatch

@inline(never)
func doit(_ n: Int) {
    guard n > 0 else {
        while true {
            pause()
        }
        return
    }
    doit(n - 1)
}

target = pthread_self()
cspl_initialize()

DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
    print("requesting sample")
    cspl_request_sample()
    print("done")
}

runWebServer()
print("DONE")
dispatchMain()

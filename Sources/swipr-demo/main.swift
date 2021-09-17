//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_implementationOnly import CProfileRecorderSampler
import NIO

import Dispatch

swipr_initialize()

DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
    swipr_request_sample()
    print("done")
}

runWebServer()
print("DONE")
dispatchMain()

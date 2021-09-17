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

import ProfileRecorder
import NIO

import Dispatch

DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
    try! ProfileRecorderSampler.sharedInstance.requestSamples(outputFilePath: "/tmp/foo",
                                                    count: 100,
                                                    timeBetweenSamples: .milliseconds(10),
                                                    eventLoop: EmbeddedEventLoop()).wait()
}

runWebServer()

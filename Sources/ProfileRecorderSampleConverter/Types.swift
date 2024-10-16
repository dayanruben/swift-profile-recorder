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
struct Sample {
    var sampleHeader: SampleHeader
    var stack: [StackFrame]

    var pid: Int {
        return self.sampleHeader.pid
    }

    var tid: Int {
        return self.sampleHeader.tid
    }

    var timeSec: Int {
        return self.sampleHeader.timeSec
    }

    var timeNSec: Int {
        return self.sampleHeader.timeNSec
    }

    var threadName: String {
        return self.sampleHeader.name
    }
}

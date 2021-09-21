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

import Foundation
import NIO

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer {
    try! group.syncShutdownGracefully()
}

let decoder = JSONDecoder()

var symboliser: Symboliser? = nil
var vmaps: [DynamicLibMapping] = []
var vmapsRead = true
var currentSample: Sample? = nil

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

var samples: [Sample] = []

while let line = readLine() {
    guard line.starts(with: "[SWIPR] ") else {
        continue
    }
    switch line.dropFirst(8).prefix(4) {
    case "MESG":
        guard let message = try? decoder.decode(Message.self, from: Data(line.dropFirst(13).utf8)) else {
            continue
        }
        print("\(message.message)")
        if let exitCode = message.exit {
            exit(exitCode)
        }
    case "VERS":
        guard let version = try? decoder.decode(Version.self, from: Data(line.dropFirst(13).utf8)) else {
            print("ERROR: Could not decode \(line) as Swift Profile Recorder version.")
            exit(EXIT_FAILURE)
        }
        guard version.version == 1 else {
            print("ERROR: This is a Swift Profile Recorder version \(version.version) trace, but we're only compatible with version 1")
            exit(EXIT_FAILURE)
        }
    case "VMAP":
        guard let mapping = try? decoder.decode(DynamicLibMapping.self, from: Data(line.dropFirst(13).utf8)) else {
            continue
        }

        if vmapsRead {
            try symboliser?.shutdown()
            symboliser = nil
            vmaps.removeAll()
            vmapsRead = false
        }
        vmaps.append(mapping)
    case "SMPL":
        vmapsRead = true
        if symboliser == nil {
            symboliser = try Symboliser(dynamicLibraryMappings: vmaps, group: group)
        }
        guard let header = try? decoder.decode(SampleHeader.self, from: Data(line.dropFirst(13).utf8)) else {
            print("failed", line.dropFirst(13))
            continue
        }

        currentSample = Sample(sampleHeader: header, stack: [])
    case "STCK":
        guard let stackFrame = try? decoder.decode(StackFrame.self, from: Data(line.dropFirst(13).utf8)) else {
            continue
        }
        currentSample?.stack.append(stackFrame)
    case "DONE":
        if let sample = currentSample, let symboliser = symboliser {
            try processModern(sample, symboliser: symboliser)
        }
    default:
        print("unknown", line.dropFirst(8).prefix(4))
        continue
    }
}

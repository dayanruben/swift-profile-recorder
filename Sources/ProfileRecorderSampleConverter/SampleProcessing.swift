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

func processModern(_ sample: Sample, printFileLine: Bool, symboliser: Symboliser) throws {
    print("\(sample.threadName)-T\(sample.tid)     \(sample.pid)/\(sample.tid)     \(sample.timeSec).\(sample.timeNSec):    swipr")
    for stackFrame in sample.stack.dropFirst() {
        for symbolicatedFrame in try symboliser.symbolise(stackFrame).allFrames {
            print("""
                  \t    \
                  \(symbolicatedFrame.address) \
                  \(symbolicatedFrame.functionName)+0x\(String(symbolicatedFrame.functionOffset, radix: 16)) \
                  (\(symbolicatedFrame.library))
                  """
                )
            if printFileLine, let file = symbolicatedFrame.file, let line = symbolicatedFrame.line {
                print("  \(file):\(line)")
            }
        }
    }
    print()
}

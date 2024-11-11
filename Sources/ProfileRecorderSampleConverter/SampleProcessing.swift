//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift Profile Recorder project authors
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
        // We would have received the instruction pointer just _behind_ the actual instruction, so to accurately
        // get the right frame, we need to get the intruction prior. On ARM that's easy (subtract 4) but on Intel
        // that's impossible so we just subtract 1 instead.
        var fixedUpStackFrame = stackFrame
        if fixedUpStackFrame.instructionPointer >= 4 {
            #if arch(arm) || arch(arm64)
            // Known fixed-width instruction format
            fixedUpStackFrame.instructionPointer -= 4
            #else
            // Unknown, subtract 1
            fixedUpStackFrame.instructionPointer -= 1
            #endif
        }

        let framesIncludingInlinedFrames = try symboliser.symbolise(fixedUpStackFrame).allFrames
        let hasMultiple = framesIncludingInlinedFrames.count > 1
        for index in framesIncludingInlinedFrames.indices {
            let symbolicatedFrame = framesIncludingInlinedFrames[index]
            let isLast = index == framesIncludingInlinedFrames.endIndex - 1

            print("""
                  \t    \
                  \(String(symbolicatedFrame.address, radix: 16)) \
                  \(symbolicatedFrame.functionName)\(hasMultiple && !isLast ? " [inlined]" :"")\
                  +0x\(String(symbolicatedFrame.functionOffset, radix: 16)) \
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

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import ProfileRecorderSampleConversion
import NIO
import Foundation
import Logging
import NIOExtras

internal class FakeSymbolizer: Symbolizer {
    func start() throws {
    }

    func symbolise(
        relativeIP: UInt,
        library: DynamicLibMapping,
        logger: Logger
    ) throws -> SymbolisedStackFrame {
        return SymbolisedStackFrame(
            allFrames: [
                SymbolisedStackFrame.SingleFrame(
                    address: relativeIP,
                    functionName: "FakeType.fakeFun\(relativeIP / 10000)()",
                    functionOffset: relativeIP % 10000,
                    library: nil,
                    vmap: library
                )
            ]
        )

    }

    func shutdown() throws {
    }

    var description: String {
        return "FakeSymbolizer"
    }
}

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

import Logging
import XCTest

@testable import ProfileRecorderSampleConversion

final class CachedSymbolizerTests: XCTestCase {
    private var symbolizer: CachedSymbolizer! = nil
    private var logger: Logger! = nil

    func testSymbolisingFrameThatIsFound() throws {
        let actual = try self.symbolizer.symbolise(StackFrame(instructionPointer: 0x2345, stackPointer: .max))
        let expected = SymbolisedStackFrame(allFrames: [
            SymbolisedStackFrame.SingleFrame(
                address: 0x1345,
                functionName: "fake",
                functionOffset: 5,
                library: "libfoo"
            )
        ])
        XCTAssertEqual(expected, actual)
    }

    func testSymbolisingFrameThatIsNotFound() throws {
        let actual = try self.symbolizer.symbolise(StackFrame(instructionPointer: 0x3000, stackPointer: .max))
        let expected = SymbolisedStackFrame(allFrames: [
            SymbolisedStackFrame.SingleFrame(
                address: 0x3000,
                functionName: "unknown @ 0x3000",
                functionOffset: 0,
                library: "unknown-lib"
            )
        ])
        XCTAssertEqual(expected, actual)
    }

    func testPerfScriptNumberRenderingSmallNumber() throws {
        let actual = try self.symbolizer.renderPerfScriptFormat(
            Sample(
                sampleHeader: SampleHeader(
                    pid: 1,
                    tid: 2,
                    name: "thread",
                    timeSec: 4,
                    timeNSec: 5 // important, this is a small number, so it'll get 0 prefixed
                ),
                stack: [
                    StackFrame(instructionPointer: 0, stackPointer: .max), // this frame will be chopped
                    StackFrame(instructionPointer: 0x2345, stackPointer: .max),
                    StackFrame(instructionPointer: 0x2999, stackPointer: .max),
                ]
            )
        )

        let expected = """
                       thread-T2     1/2     4.000000005:    swipr
                       \t    \(1345-self.instructionPointerFixup()) fake+0x5 (libfoo)
                       \t    \(1999-self.instructionPointerFixup()) fake+0x5 (libfoo)


                       """
        XCTAssertEqual(expected, actual)
    }

    func testPerfScriptNumberRenderingLargeNumber() throws {
        let actual = try self.symbolizer.renderPerfScriptFormat(
            Sample(
                sampleHeader: SampleHeader(
                    pid: 1,
                    tid: 2,
                    name: "thread",
                    timeSec: 4,
                    timeNSec: 987_654_321 // important, this is a large number, no zero prefixes
                ),
                stack: [
                    StackFrame(instructionPointer: 0, stackPointer: .max), // this frame will be chopped
                    StackFrame(instructionPointer: 0x2345, stackPointer: .max),
                    StackFrame(instructionPointer: 0x2999, stackPointer: .max),
                ]
            )
        )

        let expected = """
                       thread-T2     1/2     4.987654321:    swipr
                       \t    \(1345-self.instructionPointerFixup()) fake+0x5 (libfoo)
                       \t    \(1999-self.instructionPointerFixup()) fake+0x5 (libfoo)


                       """
        XCTAssertEqual(expected, actual)
    }

    // MARK: - Setup/teardown
    override func setUpWithError() throws {
        self.logger = Logger(label: "\(Self.self)")
        self.logger.logLevel = .info

        let fakeSym = FakeSymbolizer()
        self.symbolizer = try CachedSymbolizer(
            configuration: SymbolizerConfiguration(perfScriptOutputWithFileLineInformation: false),
            symbolizer: fakeSym,
            dynamicLibraryMappings: [
                DynamicLibMapping(
                    path: "/lib/libfoo.so",
                    fileMappedAddress: 0x1000,
                    segmentStartAddress: 0x2000,
                    segmentEndAddress: 0x3000
                )
            ],
            group: .singletonMultiThreadedEventLoopGroup,
            logger: self.logger
        )
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.symbolizer.shutdown())
        self.symbolizer = nil
        self.logger = nil
    }

    // MARK: - Helpers
    func instructionPointerFixup() -> Int {
#if arch(arm) || arch(arm64)
        // Known fixed-width instruction format
        return 4
#else
        // Unknown, subtract 1
        return 1
#endif
    }
}

final class FakeSymbolizer: Symbolizer {
    func start() throws {
    }

    func symbolise(
        relativeIP: UInt,
        library: ProfileRecorderSampleConversion.DynamicLibMapping,
        logger: Logging.Logger
    ) throws -> ProfileRecorderSampleConversion.SymbolisedStackFrame {
        return SymbolisedStackFrame(
            allFrames: [
                SymbolisedStackFrame.SingleFrame(
                    address: relativeIP,
                    functionName: "fake",
                    functionOffset: 5,
                    library: "libfoo"
                )
            ]
        )
    }

    func shutdown() throws {
    }
}

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

import Atomics
import XCTest
import NIO
import NIOConcurrencyHelpers
import Logging
import _NIOFileSystem
@testable import ProfileRecorder

final class ProfileRecorderTests: XCTestCase {
    var tempDirectory: String! = nil
    var group: EventLoopGroup! = nil
    var logger: Logger! = nil

    func testBasicJustRequestOneSample() throws {
        XCTAssertNoThrow(try
                         ProfileRecorderSampler.sharedInstance.requestSamples(outputFilePath: "\(self.tempDirectory!)/samples.samples",
                                                                    count: 1,
                                                                    timeBetweenSamples: .nanoseconds(0),
                                                                    eventLoop: self.group.next()).wait())
    }

    func testMultipleSamples() throws {
        XCTAssertNoThrow(try
                         ProfileRecorderSampler.sharedInstance.requestSamples(outputFilePath: "\(self.tempDirectory!)/samples.samples",
                                                                    count: 10,
                                                                    timeBetweenSamples: .nanoseconds(0),
                                                                    eventLoop: self.group.next()).wait())
    }

    func testSamplingWithALargeNumberOfThreads() throws {
        let threads = NIOThreadPool(numberOfThreads: 128)
        threads.start()
        defer {
            XCTAssertNoThrow(try threads.syncShutdownGracefully())
        }

        XCTAssertNoThrow(try
                         ProfileRecorderSampler.sharedInstance.requestSamples(outputFilePath: "\(self.tempDirectory!)/samples.samples",
                                                                    count: 100,
                                                                    timeBetweenSamples: .nanoseconds(0),
                                                                    eventLoop: self.group.next()).wait())
    }

    func testSamplingWhilstThreadsAreCreatedAndDying() throws {
        let samples = ProfileRecorderSampler.sharedInstance.requestSamples(outputFilePath: "\(self.tempDirectory!)/samples.samples",
                                                                 count: 1000,
                                                                 timeBetweenSamples: .microseconds(100),
                                                                 eventLoop: self.group.next())
        let keepRunning = ManagedAtomic<Bool>(true)
        samples.whenComplete { _ in
            keepRunning.store(false, ordering: .relaxed)
        }
        while keepRunning.load(ordering: .relaxed) {
            XCTAssertNoThrow(try MultiThreadedEventLoopGroup(numberOfThreads: 64).syncShutdownGracefully())
        }

        XCTAssertNoThrow(try samples.wait())
    }

    func testSymbolicatedSamplesWork() async throws {
        guard ProfileRecorderSampler.isSupportedPlatform else {
            return
        }

        let reachedQuuuxSem = DispatchSemaphore(value: 0)
        let unblockSem = DispatchSemaphore(value: 0)
        self.logger.info("spawning thread")
        Thread {
            RECGONISABLE_FUNCTION_FOO(reachedQuuuxSem: reachedQuuuxSem, unblockSem: unblockSem)
        }.start()
        self.logger.info("waiting for conds")
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                reachedQuuuxSem.wait()
                cont.resume()
            }
        }
        self.logger.info("done")

        // okay, we should have a thread blocked in RECGONISABLE_FUNCTION_QUUUX() now

        let sampleBytes = try await ProfileRecorderSampler.sharedInstance.withSymbolizedSamplesInPerfScriptFormat(
            sampleCount: 1,
            timeBetweenSamples: .nanoseconds(0),
            logger: self.logger
        ) { file in
            try await ByteBuffer(contentsOf: FilePath(file), maximumSizeAllowed: .unlimited)
        }
        let samples = String(buffer: sampleBytes).split(separator: "\n")
        for index in samples.indices {
            let currentLine = samples[index]
            guard currentLine.contains("RECGONISABLE_FUNCTION_QUUUX") else {
                continue
            }
            let interestingLines = Array(samples.dropFirst(index).prefix(6))
            guard interestingLines.count == 6 else {
                XCTFail("Expected 6 lines, got \(interestingLines.count) in \(interestingLines)")
                return
            }
            XCTAssert(interestingLines[0].contains("RECGONISABLE_FUNCTION_QUUUX"), "\(interestingLines[0])")
            XCTAssert(interestingLines[1].contains("RECGONISABLE_FUNCTION_QUUX"), "\(interestingLines[1])")
            XCTAssert(interestingLines[2].contains("RECGONISABLE_FUNCTION_QUX"), "\(interestingLines[2])")
            XCTAssert(interestingLines[3].contains("RECGONISABLE_FUNCTION_BUZ"), "\(interestingLines[3])")
            XCTAssert(interestingLines[4].contains("RECGONISABLE_FUNCTION_BAR"), "\(interestingLines[4])")
            XCTAssert(interestingLines[5].contains("RECGONISABLE_FUNCTION_FOO"), "\(interestingLines[5])")
        }
    }

    // MARK: - Setup/teardown
    override func setUp() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        self.tempDirectory = NSTemporaryDirectory() + "/ProfileRecorderTests-\(UUID())"
        XCTAssertNoThrow(try FileManager.default.createDirectory(atPath: self.tempDirectory,
                                                                 withIntermediateDirectories: false))
        self.logger = Logger(label: "ProfileRecorderTests")
    }

    override func tearDown() {
        self.logger = nil
        XCTAssertNoThrow(try self.group.syncShutdownGracefully())
        self.group = nil

        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: self.tempDirectory))
        self.tempDirectory = nil
    }
}

func RECGONISABLE_FUNCTION_FOO(reachedQuuuxSem: DispatchSemaphore, unblockSem: DispatchSemaphore) {
    RECGONISABLE_FUNCTION_BAR(reachedQuuuxSem: reachedQuuuxSem, unblockSem: unblockSem)
}

func RECGONISABLE_FUNCTION_BAR(reachedQuuuxSem: DispatchSemaphore, unblockSem: DispatchSemaphore) {
    RECGONISABLE_FUNCTION_BUZ(reachedQuuuxSem: reachedQuuuxSem, unblockSem: unblockSem)
}

func RECGONISABLE_FUNCTION_BUZ(reachedQuuuxSem: DispatchSemaphore, unblockSem: DispatchSemaphore) {
    RECGONISABLE_FUNCTION_QUX(reachedQuuuxSem: reachedQuuuxSem, unblockSem: unblockSem)
}

func RECGONISABLE_FUNCTION_QUX(reachedQuuuxSem: DispatchSemaphore, unblockSem: DispatchSemaphore) {
    RECGONISABLE_FUNCTION_QUUX(reachedQuuuxSem: reachedQuuuxSem, unblockSem: unblockSem)
}

func RECGONISABLE_FUNCTION_QUUX(reachedQuuuxSem: DispatchSemaphore, unblockSem: DispatchSemaphore) {
    RECGONISABLE_FUNCTION_QUUUX(reachedQuuuxSem: reachedQuuuxSem, unblockSem: unblockSem)
}

func RECGONISABLE_FUNCTION_QUUUX(reachedQuuuxSem: DispatchSemaphore, unblockSem: DispatchSemaphore) {
    reachedQuuuxSem.signal()
    unblockSem.wait()
}

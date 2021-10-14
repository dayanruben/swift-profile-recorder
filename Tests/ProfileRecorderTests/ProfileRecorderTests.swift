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

import XCTest
import NIO
import NIOConcurrencyHelpers
@testable import ProfileRecorder

final class ProfileRecorderTests: XCTestCase {
    var tempDirectory: String! = nil
    var group: EventLoopGroup! = nil

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
        let keepRunning = NIOAtomic<Bool>.makeAtomic(value: true)
        samples.whenComplete { _ in
            keepRunning.store(false)
        }
        while keepRunning.load() {
            XCTAssertNoThrow(try MultiThreadedEventLoopGroup(numberOfThreads: 64).syncShutdownGracefully())
        }

        XCTAssertNoThrow(try samples.wait())
    }

    // MARK: - Setup/teardown
    override func setUp() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        self.tempDirectory = NSTemporaryDirectory() + "/ProfileRecorderTests-\(UUID())"
        XCTAssertNoThrow(try FileManager.default.createDirectory(atPath: self.tempDirectory,
                                                                 withIntermediateDirectories: false))
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.group.syncShutdownGracefully())
        self.group = nil

        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: self.tempDirectory))
        self.tempDirectory = nil
    }
}

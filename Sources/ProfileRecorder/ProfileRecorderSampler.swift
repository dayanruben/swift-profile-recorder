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
import NIO
@_implementationOnly import CProfileRecorderSampler

private let globalProfileRecorder: ProfileRecorderSampler = {
    swipr_initialize()
    return ProfileRecorderSampler()
}()

public final class ProfileRecorderSampler {
    private let threadPool: NIOThreadPool

    public static var sharedInstance: ProfileRecorderSampler {
        return globalProfileRecorder
    }

    fileprivate init() {
        self.threadPool = NIOThreadPool(numberOfThreads: 1)
        self.threadPool.start()
    }

    private func requestSamples(output: UnsafeMutablePointer<FILE>,
                                count: Int,
                                timeBetweenSamples: TimeAmount,
                                eventLoop: EventLoop) -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: eventLoop) {
            swipr_request_sample(output, .init(count), .init(timeBetweenSamples.nanoseconds / 1000))
        }
    }

    public func requestSamples(outputFilePath: String,
                               count: Int,
                               timeBetweenSamples: TimeAmount,
                               eventLoop: EventLoop) -> EventLoopFuture<Void> {
        if outputFilePath == "-" {
            return self.requestSamples(output: stderr,
                                       count: count, timeBetweenSamples: timeBetweenSamples, eventLoop: eventLoop)
        } else {
            let output = fopen(outputFilePath, "w");
            guard let output = output else {
                struct CouldNotOpenFileError: Error {
                    var path: String
                }
                return eventLoop.makeFailedFuture(CouldNotOpenFileError(path: outputFilePath))
            }

            return self.requestSamples(output: output,
                                       count: count,
                                       timeBetweenSamples: timeBetweenSamples,
                                       eventLoop: eventLoop).always { _ in
                fclose(output)
            }
        }
    }
}

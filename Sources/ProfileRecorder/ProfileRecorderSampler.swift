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
import Dispatch
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
        return self.threadPool.runIfActive(eventLoop: eventLoop) {
            swipr_request_sample(output, .init(count), .init(timeBetweenSamples.nanoseconds / 1000))
        }
    }

    public func requestSamples(outputFilePath: String,
                               failIfFileExists: Bool = true,
                               count: Int,
                               timeBetweenSamples: TimeAmount,
                               queue: DispatchQueue,
                               _ handler: @escaping (Result<String, Error>) -> Void) {
        self.requestSamples(outputFilePath: outputFilePath,
                            failIfFileExists: failIfFileExists,
                            count: count,
                            timeBetweenSamples: timeBetweenSamples,
                            // FIXME: EmbeddedEventLoop is a hack here...
                            eventLoop: EmbeddedEventLoop()).whenComplete { result in
            queue.async {
                handler(result.map { outputFilePath })
            }
        }
    }

    public func requestSamples(outputFilePath: String,
                               failIfFileExists: Bool = true,
                               count: Int,
                               timeBetweenSamples: TimeAmount,
                               eventLoop: EventLoop) -> EventLoopFuture<Void> {
        if outputFilePath == "-" {
            return self.requestSamples(output: stderr,
                                       count: count, timeBetweenSamples: timeBetweenSamples, eventLoop: eventLoop)
        } else {
            guard let output = fopen(outputFilePath, "w\(failIfFileExists ? "x" : "")") else {
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

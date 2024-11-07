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
#if canImport(CProfileRecorderSampler) // only on macOS & Linux
@_implementationOnly import CProfileRecorderSampler
#endif

private let globalProfileRecorder: ProfileRecorderSampler = {
#if canImport(CProfileRecorderSampler) // only on macOS & Linux
    swipr_initialize()
#endif
    return ProfileRecorderSampler()
}()

struct CouldNotOpenFileError: Error {
    var path: String
}

public final class ProfileRecorderSampler: Sendable {
    private let threadPool: NIOThreadPool

    internal struct UnsupportedOperation: Error {}

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
#if canImport(CProfileRecorderSampler) // only on macOS & Linux
        return self.threadPool.runIfActive(eventLoop: eventLoop) {
            swipr_request_sample(output, .init(count), .init(timeBetweenSamples.nanoseconds / 1000))
        }
#else
        return eventLoop.makeFailedFuture(UnsupportedOperation())
#endif
    }

    public func requestSamples(outputFilePath: String,
                               failIfFileExists: Bool = true,
                               count: Int,
                               timeBetweenSamples: TimeAmount,
                               queue: DispatchQueue,
                               _ handler: @Sendable @escaping (Result<String, Error>) -> Void) {
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

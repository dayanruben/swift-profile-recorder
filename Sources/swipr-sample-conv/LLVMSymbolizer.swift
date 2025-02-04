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

import ProfileRecorderSampleConversion
import NIO
import Foundation
import Logging
import NIOExtras

public struct LLVMSymboliserConfig: Sendable {
    var viaJSON: Bool
    var unstuckerWorkaround: Bool
}

/// Symbolises `StackFrame`s using `llvm-symbolizer`.
///
/// Not thread-safe.
internal class LLVMSymboliser: Symbolizer {
    private let group: EventLoopGroup
    private var process: Process? = nil
    private var channel: Channel? = nil
    private var unstucker: RepeatedTask? = nil
    private let logger: Logger
    private let config: LLVMSymboliserConfig

    internal init(
        config: LLVMSymboliserConfig,
        group: EventLoopGroup,
        logger: Logger
    ) {
        self.config = config
        self.group = group
        self.logger = logger
    }

    internal func start() throws {
        let stdIn = Pipe()
        let stdOut = Pipe()

        let p = Process()
        p.standardInput = stdIn.fileHandleForReading
        p.standardOutput = stdOut.fileHandleForWriting
        let symboliserPath: String
        if let path = ProcessInfo.processInfo.environment["SWIPR_LLVM_SYMBOLIZER"] {
            symboliserPath = path
        } else {
            symboliserPath = "/usr/bin/llvm-symbolizer"
        }

        p.executableURL = URL(fileURLWithPath: symboliserPath)
        p.arguments = [
            "--print-address",
            "--demangle",
            "--inlining=true",
            "--functions=linkage",
            "--basenames",
        ] + (self.config.viaJSON ? ["--output-style=JSON"] : [])
        try p.run()
        self.process = p

        let channel: Channel = try NIOPipeBootstrap(group: self.group)
            .channelInitializer { [
                logger = self.logger,
                viaJSON = self.config.viaJSON
            ] channel in
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    viaJSON ? LLVMJSONOutputParserHandler() : LLVMOutputParserHandler(),
                    LLVMSymbolizerEncoderHandler(logger: logger),
                    LogErrorHandler(logger: logger),
                    RequestResponseHandler<LLVMSymbolizerQuery, SymbolisedStackFrame>()
                ])
            }
            .takingOwnershipOfDescriptors(
                input: dup(stdOut.fileHandleForReading.fileDescriptor),
                output: dup(stdIn.fileHandleForWriting.fileDescriptor)
            ).wait()
        self.channel = channel
        if self.config.unstuckerWorkaround {
            self.unstucker = channel.eventLoop.scheduleRepeatedTask(initialDelay: .milliseconds(1000),
                                                                    delay: .milliseconds(1000)) { _ in
                let p = channel.eventLoop.makePromise(of: SymbolisedStackFrame.self)
                channel.writeAndFlush((StackFrame(instructionPointer: .max, stackPointer: 0), p)).cascadeFailure(to: p)
                p.futureResult.whenSuccess { str in
                    if !(str.allFrames.first?.address ?? 0 == .max) {
                        fputs("unexpected PING message result '\(str)'\n", stderr)
                    }
                }
            }
        }
    }

    internal func symbolise(
        relativeIP: UInt,
        library: DynamicLibMapping,
        logger: Logger
    ) throws -> SymbolisedStackFrame {
        struct TimeoutError: Error {
            var relativeIP: UInt
            var library: DynamicLibMapping
        }
        let promise = self.channel!.eventLoop.makePromise(of: SymbolisedStackFrame.self)
        let sched = promise.futureResult.eventLoop.scheduleTask(in: .seconds(10)) {
            promise.fail(TimeoutError(relativeIP: relativeIP, library: library))
        }
        do {
            let query = LLVMSymbolizerQuery(address: relativeIP, library: library)
            try self.channel!.writeAndFlush((query, promise)).wait()
        } catch {
            self.logger.error("write to llvm-symbolizer pipe failed", metadata: ["error": "\(error)"])
            promise.fail(error)
        }
        promise.futureResult.whenComplete { _ in
            sched.cancel()
        }
        return try promise.futureResult.wait()
    }

    internal func shutdown() throws {
        self.logger.debug("shutting down")
        self.unstucker?.cancel(promise: nil)

        self.process?.terminate()
        self.process = nil

        do {
            try self.channel?.close().wait()
        } catch ChannelError.alreadyClosed {
            // ok
        }
        self.channel = nil
    }

    deinit {
        assert(self.channel == nil)
        assert(self.process == nil)
    }

    public var description: String {
        return "LLVMSymbolizer"
    }
}

final class LogErrorHandler: ChannelInboundHandler {
    typealias InboundIn = NIOAny

    let logger: Logger

    internal init(logger: Logger) {
        self.logger = logger
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        defer {
            context.fireErrorCaught(error)
        }
        self.logger.warning("error whilst interacting with llvm-symbolizer", metadata: ["error": "\(error)"])
    }
}

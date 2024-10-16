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

import NIO
import Foundation
import NIOExtras
import Logging

/// Symbolises `StackFrame`s.
///
/// Not thread-safe.
public class Symboliser {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let group: EventLoopGroup
    private let llvmSymboliser: LLVMSymboliser
    private var cache: [UInt: String] = [:]

    public init(
        dynamicLibraryMappings: [DynamicLibMapping],
        group: EventLoopGroup,
        logger: Logger
    ) throws {
        self.dynamicLibraryMappings = dynamicLibraryMappings
        self.group = group
        self.llvmSymboliser = LLVMSymboliser(
            dynamicLibraryMappings: dynamicLibraryMappings,
            group: group,
            logger: logger
        )
        try self.llvmSymboliser.start()
    }

    public func symbolise(_ stackFrame: StackFrame) throws -> String {
        if let symd = self.cache[stackFrame.instructionPointer] {
            return symd
        } else {
            let symd = try self.llvmSymboliser.symbolise(stackFrame)
            self.cache[stackFrame.instructionPointer] = symd
            return symd
        }
    }

    public func shutdown() throws {
        try self.llvmSymboliser.shutdown()
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

/// Symbolises `StackFrame`s using `llvm-symbolizer`.
///
/// Not thread-safe.
internal class LLVMSymboliser {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let group: EventLoopGroup
    private var process: Process? = nil
    private var channel: Channel? = nil
    private var unstucker: RepeatedTask? = nil
    private let logger: Logger

    internal init(dynamicLibraryMappings: [DynamicLibMapping], group: EventLoopGroup, logger: Logger) {
        self.dynamicLibraryMappings = dynamicLibraryMappings
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
            "--color=1"
        ]
        try p.run()
        self.process = p

        let channel: Channel = try NIOPipeBootstrap(group: self.group)
            .channelInitializer { [
                dynamicLibraryMappings = self.dynamicLibraryMappings,
                logger = self.logger
            ] channel in
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    LLVMOutputParserHandler(),
                    LLVMStackFrameEncoderHandler(dynamicLibraryMappings: dynamicLibraryMappings),
                    LogErrorHandler(logger: logger),
                    RequestResponseHandler<StackFrame, String>()
                    ])
            }
            .takingOwnershipOfDescriptors(
                input: dup(stdOut.fileHandleForReading.fileDescriptor),
                output: dup(stdIn.fileHandleForWriting.fileDescriptor)
            ).wait()
        self.channel = channel
        self.unstucker = channel.eventLoop.scheduleRepeatedTask(initialDelay: .milliseconds(100),
                                                                delay: .milliseconds(10)) { _ in
            let p = channel.eventLoop.makePromise(of: String.self)
            channel.writeAndFlush((StackFrame(instructionPointer: .max, stackPointer: 0), p)).cascadeFailure(to: p)
            p.futureResult.whenSuccess { str in
                if !str.starts(with: "0xffffffffffffffff") {
                    fputs("unexpected PING message result '\(str)'\n", stderr)
                }
            }
        }
    }

    internal func symbolise(_ stackFrame: StackFrame) throws -> String {
        struct TimeoutError: Error {
            var stackFrame: StackFrame
            var allMappings: [DynamicLibMapping]
            var matchingMappings: [DynamicLibMapping]
        }
        let promise = self.channel!.eventLoop.makePromise(of: String.self)
        let sched = promise.futureResult.eventLoop.scheduleTask(
            in: .seconds(10)
        ) { [dynamicLibraryMappings = self.dynamicLibraryMappings] in
            promise.fail(TimeoutError(stackFrame: stackFrame,
                                      allMappings: dynamicLibraryMappings,
                                      matchingMappings: dynamicLibraryMappings.filter { mapping in
                stackFrame.instructionPointer >= mapping.segmentStartAddress && stackFrame.instructionPointer < mapping.segmentEndAddress
            }))
        }
        do {
            try self.channel!.writeAndFlush((stackFrame, promise)).wait()
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
}

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
import Foundation
import NIOExtras

/// Symbolises `StackFrame`s.
///
/// Not thread-safe.
public class Symboliser {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let group: EventLoopGroup
    private let llvmSymboliser: LLVMSymboliser
    private var cache: [UInt: String] = [:]

    public init(dynamicLibraryMappings: [DynamicLibMapping], group: EventLoopGroup) throws {
        self.dynamicLibraryMappings = dynamicLibraryMappings
        self.group = group
        self.llvmSymboliser = LLVMSymboliser(dynamicLibraryMappings: dynamicLibraryMappings, group: group)
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

/// Symbolises `StackFrame`s using `llvm-symbolizer`.
///
/// Not thread-safe.
internal class LLVMSymboliser {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let group: EventLoopGroup
    private var process: Process? = nil
    private var channel: Channel? = nil

    internal init(dynamicLibraryMappings: [DynamicLibMapping], group: EventLoopGroup) {
        self.dynamicLibraryMappings = dynamicLibraryMappings
        self.group = group
    }

    internal func start() throws {
        let stdIn = Pipe()
        let stdOut = Pipe()

        let p = Process()
        p.standardInput = stdIn.fileHandleForReading
        p.standardOutput = stdOut.fileHandleForWriting
        p.executableURL = URL(fileURLWithPath: "/usr/bin/llvm-symbolizer")
        p.arguments = ["--use-symbol-table=true", "--print-address", "--demangle=1", "--inlining=true", "--functions=linkage", "--color=1"]
        try p.run()
        self.process = p

        let channel: Channel = try NIOPipeBootstrap(group: self.group)
            .channelInitializer { channel in
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    LLVMOutputParserHandler(),
                    LLVMStackFrameEncoderHandler(dynamicLibraryMappings: self.dynamicLibraryMappings),
                    RequestResponseHandler<StackFrame, String>()
                    ])
            }
            .withPipes(inputDescriptor: dup(stdOut.fileHandleForReading.fileDescriptor),
                       outputDescriptor: dup(stdIn.fileHandleForWriting.fileDescriptor))
            .wait()
        self.channel = channel
    }

    internal func symbolise(_ stackFrame: StackFrame) throws -> String {
        let promise = self.channel!.eventLoop.makePromise(of: String.self)
        try self.channel!.writeAndFlush((stackFrame, promise)).wait()
        return try promise.futureResult.wait()
    }

    internal func shutdown() throws {
        self.process?.terminate()
        self.process = nil

        try self.channel?.close().wait()
        self.channel = nil
    }

    deinit {
        assert(self.channel == nil)
        assert(self.process == nil)
    }
}

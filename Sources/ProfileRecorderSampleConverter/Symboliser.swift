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

import NIO
import Foundation
import NIOExtras
import Logging

public struct SymbolisedStackFrame: Sendable {
    internal struct SingleFrame: Sendable {
        var address: UInt
        var functionName: String
        var functionOffset: UInt
        var library: String
        var file: Optional<String>
        var line: Optional<Int>
    }

    var allFrames: [SingleFrame]
}

protocol Symbolizer {
    func start() throws
    func symbolise(_ stackFrame: StackFrame) throws -> SymbolisedStackFrame
    func shutdown() throws
}

enum AnyElfImage {
    case elf32(Elf32Image)
    case elf64(Elf64Image)

    func lookupRealAndInlinedFrames(address: UInt64) -> [ImageSymbol]? {
        switch self {
        case .elf32(let image):
            guard let realFrame = image.lookupSymbol(address: UInt32(truncatingIfNeeded: address)) else {
                return nil
            }
            var symbols: [ImageSymbol] = []
            for inlineFrame in image.inlineCallSites(at: UInt32(truncatingIfNeeded: address)).reversed() {
                symbols.append(
                    ImageSymbol(
                        name: inlineFrame.name ?? "unknown in \(inlineFrame.filename)",
                        offset: 0
                    )
                )
            }
            symbols.append(realFrame)
            return symbols
        case .elf64(let image):
            guard let realFrame = image.lookupSymbol(address: address) else {
                return nil
            }

            var symbols: [ImageSymbol] = []
            for inlineFrame in image.inlineCallSites(at: address).reversed() {
                symbols.append(
                    ImageSymbol(
                        name: inlineFrame.name ?? "unknown in \(inlineFrame.filename)",
                        offset: 0
                    )
                )
            }
            symbols.append(realFrame)
            return symbols
        }
    }

    func sourceLocation(for address: UInt64) throws -> SourceLocation? {
        switch self {
        case .elf32(let image):
            return try image.sourceLocation(for: UInt32(truncatingIfNeeded: address))
        case .elf64(let image):
            return try image.sourceLocation(for: address)
        }
    }
}

public class NativeSymboliser: Symbolizer {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private var elfSourceCache: [String: AnyElfImage] = [:]

    public init(dynamicLibraryMappings: [DynamicLibMapping]) {
        self.dynamicLibraryMappings = dynamicLibraryMappings
    }

    public func start() throws {}

    public func symbolise(_ stackFrame: StackFrame) throws -> SymbolisedStackFrame {
        let matched = self.dynamicLibraryMappings.filter { mapping in
            stackFrame.instructionPointer >= mapping.segmentStartAddress &&
            stackFrame.instructionPointer < mapping.segmentEndAddress
        }.first

        lazy var failed = SymbolisedStackFrame(
            allFrames: [SymbolisedStackFrame.SingleFrame(
                address: stackFrame.instructionPointer - (matched?.segmentStartAddress ?? 0),
                functionName: "\(stackFrame.instructionPointer)",
                functionOffset: 0,
                library: "unknown-lib",
                file: nil,
                line: nil
            )]
        )

        guard let matched = matched else {
            return failed
        }

        var elfImage: AnyElfImage? = self.elfSourceCache[matched.path]
        if elfImage == nil {
            if let source = try? ImageSource(path: matched.path) {
                if let image = try? Elf32Image(source: source) {
                    elfImage = .elf32(image)
                } else if let image = try? Elf64Image(source: source) {
                    elfImage = .elf64(image)
                } else {
                    elfImage = nil
                }
            }
            self.elfSourceCache[matched.path] = elfImage
        }
        guard let elfImage = elfImage else {
            return failed
        }

        let results = elfImage.lookupRealAndInlinedFrames(
            address: UInt64(stackFrame.instructionPointer - matched.segmentStartAddress)
        )

        guard let results = results else {
            return failed
        }
        return SymbolisedStackFrame(
            allFrames: results.map { result in SymbolisedStackFrame.SingleFrame(
                address: stackFrame.instructionPointer - matched.segmentStartAddress,
                functionName: result.name,
                functionOffset: UInt(exactly: result.offset) ?? 0,
                library: matched.path,
                file: nil,
                line: nil
            )
            }
        )
    }

    public func shutdown() throws {}
}

/// Symbolises `StackFrame`s.
///
/// Not thread-safe.
public class Symboliser {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let group: EventLoopGroup
    private let symbolizer: any Symbolizer
    private var cache: [UInt: SymbolisedStackFrame] = [:]

    public init(
        useNativeSymbolizer: Bool,
        llvmSymboliserConfig: LLVMSymboliserConfig,
        dynamicLibraryMappings: [DynamicLibMapping],
        group: EventLoopGroup,
        logger: Logger
    ) throws {
        self.dynamicLibraryMappings = dynamicLibraryMappings
        self.group = group
        if useNativeSymbolizer {
            self.symbolizer = NativeSymboliser(dynamicLibraryMappings: dynamicLibraryMappings)
        } else {
            self.symbolizer = LLVMSymboliser(
                config: llvmSymboliserConfig,
                dynamicLibraryMappings: dynamicLibraryMappings,
                group: group,
                logger: logger
            )
        }
        try self.symbolizer.start()
    }

    public func symbolise(_ stackFrame: StackFrame) throws -> SymbolisedStackFrame {
        if let symd = self.cache[stackFrame.instructionPointer] {
            return symd
        } else {
            let symd = try self.symbolizer.symbolise(stackFrame)
            self.cache[stackFrame.instructionPointer] = symd
            return symd
        }
    }

    public func shutdown() throws {
        try self.symbolizer.shutdown()
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

public struct LLVMSymboliserConfig: Sendable {
    var viaJSON: Bool
    var unstuckerWorkaround: Bool
}

/// Symbolises `StackFrame`s using `llvm-symbolizer`.
///
/// Not thread-safe.
internal class LLVMSymboliser: Symbolizer {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let group: EventLoopGroup
    private var process: Process? = nil
    private var channel: Channel? = nil
    private var unstucker: RepeatedTask? = nil
    private let logger: Logger
    private let config: LLVMSymboliserConfig

    internal init(
        config: LLVMSymboliserConfig,
        dynamicLibraryMappings: [DynamicLibMapping],
        group: EventLoopGroup,
        logger: Logger
    ) {
        self.config = config
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
            "--basenames",
        ] + (self.config.viaJSON ? ["--output-style=JSON"] : [])
        try p.run()
        self.process = p

        let channel: Channel = try NIOPipeBootstrap(group: self.group)
            .channelInitializer { [
                dynamicLibraryMappings = self.dynamicLibraryMappings,
                logger = self.logger,
                viaJSON = self.config.viaJSON
            ] channel in
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    viaJSON ? LLVMJSONOutputParserHandler() : LLVMOutputParserHandler(),
                    LLVMStackFrameEncoderHandler(dynamicLibraryMappings: dynamicLibraryMappings),
                    LogErrorHandler(logger: logger),
                    RequestResponseHandler<StackFrame, SymbolisedStackFrame>()
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

    internal func symbolise(_ stackFrame: StackFrame) throws -> SymbolisedStackFrame {
        struct TimeoutError: Error {
            var stackFrame: StackFrame
            var allMappings: [DynamicLibMapping]
            var matchingMappings: [DynamicLibMapping]
        }
        let promise = self.channel!.eventLoop.makePromise(of: SymbolisedStackFrame.self)
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

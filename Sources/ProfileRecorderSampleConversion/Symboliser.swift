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
    public struct SingleFrame: Sendable {
        public var address: UInt
        public var functionName: String
        public var functionOffset: UInt
        public var library: String
        public var file: Optional<String>
        public var line: Optional<Int>

        public init(
            address: UInt,
            functionName: String,
            functionOffset: UInt,
            library: String,
            file: Optional<String> = nil,
            line: Optional<Int> = nil
        ) {
            self.address = address
            self.functionName = functionName
            self.functionOffset = functionOffset
            self.library = library
            self.file = file
            self.line = line
        }
    }

    public var allFrames: [SingleFrame]

    public init(allFrames: [SymbolisedStackFrame.SingleFrame]) {
        self.allFrames = allFrames
    }
}

public protocol Symbolizer {
    @available(*, noasync, message: "blocks the calling thread")
    func start() throws

    @available(*, noasync, message: "blocks the calling thread")
    func symbolise(relativeIP: UInt, library: DynamicLibMapping, logger: Logger) throws -> SymbolisedStackFrame

    @available(*, noasync, message: "blocks the calling thread")
    func shutdown() throws
}

enum AnyElfImage {
    case elf32(Elf32Image)
    case elf64(Elf64Image)

    func lookupRealAndInlinedFrames(address: UInt64, logger: Logger) -> [ImageSymbol]? {
        switch self {
        case .elf32(let image):
            guard let realFrame = image.lookupSymbol(address: UInt32(truncatingIfNeeded: address)) else {
                logger.trace(
                    "could not find symbol",
                    metadata: [
                        "address": "0x\(String(address, radix: 16))",
                        "image": "\(image)",
                        "image-name": "\(image.imageName)",
                        "inline-frames": "\(image.inlineCallSites(at: UInt32(truncatingIfNeeded: address)))"
                    ]
                )
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
                logger.trace(
                    "could not find symbol",
                    metadata: [
                        "address": "0x\(String(address, radix: 16))",
                        "image": "\(image)",
                        "image-name": "\(image.imageName)",
                        "inline-frames": "\(image.inlineCallSites(at: address))"
                    ]
                )
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
    private var elfSourceCache: [String: AnyElfImage] = [:]

    public init() {}

    public func start() throws {}

    public func symbolise(relativeIP: UInt, library: DynamicLibMapping, logger: Logger) throws -> SymbolisedStackFrame {
        lazy var failed = SymbolisedStackFrame(
            allFrames: [SymbolisedStackFrame.SingleFrame(
                address: relativeIP,
                functionName: "unknown @ 0x\(String(relativeIP, radix: 16))",
                functionOffset: 0,
                library: library.path,
                file: nil,
                line: nil
            )]
        )

        var elfImage: AnyElfImage? = self.elfSourceCache[library.path]
        if elfImage == nil {
            if let source = try? ImageSource(path: library.path) {
                if let image = try? Elf32Image(source: source) {
                    elfImage = .elf32(image)
                } else if let image = try? Elf64Image(source: source) {
                    elfImage = .elf64(image)
                } else {
                    elfImage = nil
                }
            }
            self.elfSourceCache[library.path] = elfImage
        }
        guard let elfImage = elfImage else {
            return failed
        }

        let results = elfImage.lookupRealAndInlinedFrames(address: UInt64(relativeIP), logger: logger)

        guard let results = results else {
            return failed
        }
        return SymbolisedStackFrame(
            allFrames: results.map { result in SymbolisedStackFrame.SingleFrame(
                address: relativeIP,
                functionName: result.name,
                functionOffset: UInt(exactly: result.offset) ?? 0,
                library: library.path,
                file: nil,
                line: nil
            )
            }
        )
    }

    public func shutdown() throws {}
}

public struct SymbolizerConfiguration: Sendable {
    public var perfScriptOutputWithFileLineInformation: Bool

    public static var `default`: SymbolizerConfiguration {
        return SymbolizerConfiguration(perfScriptOutputWithFileLineInformation: false)
    }
}

/// Symbolises `StackFrame`s.
///
/// Not thread-safe.
public class CachedSymbolizer {
    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let group: EventLoopGroup
    private let symbolizer: any Symbolizer
    private let logger: Logger
    private var cache: [UInt: SymbolisedStackFrame] = [:]
    private var configuration: SymbolizerConfiguration

    public init(
        configuration: SymbolizerConfiguration,
        symbolizer: some Symbolizer,
        dynamicLibraryMappings: [DynamicLibMapping],
        group: EventLoopGroup,
        logger: Logger
    ) throws {
        self.configuration = configuration
        self.dynamicLibraryMappings = dynamicLibraryMappings.sorted(by: { l, r in
            return l.segmentStartAddress < r.segmentStartAddress
        })
        self.group = group
        self.symbolizer = symbolizer
        self.logger = logger
        logger.trace("starting CachedSymbolizer", metadata: ["mappings": "\(self.dynamicLibraryMappings)"])
        try self.symbolizer.start()
    }

    private func symboliseSlow(_ stackFrame: StackFrame) throws -> SymbolisedStackFrame {
        // TODO: Just binary search this, it's already sorted
        let matched = self.dynamicLibraryMappings.filter { mapping in
            stackFrame.instructionPointer >= mapping.segmentStartAddress &&
            stackFrame.instructionPointer < mapping.segmentEndAddress
        }.first

        if _isDebugAssertConfiguration() {
            let allMatched = self.dynamicLibraryMappings.filter { mapping in
                stackFrame.instructionPointer >= mapping.segmentStartAddress &&
                stackFrame.instructionPointer < mapping.segmentEndAddress
            }
            if allMatched.count > 1 {
                self.logger.error(
                    "found multiple matches for instruction pointer",
                    metadata: [
                        "ip": "0x\(String(stackFrame.instructionPointer, radix: 16))",
                        "mappings": "\(allMatched)"
                    ]
                )
            }
        }

        guard let matched = matched else {
            self.logger.debug(
                "could not match instruction pointer",
                metadata: [
                    "ip": "0x\(String(stackFrame.instructionPointer, radix: 16))"
                ]
            )
            return SymbolisedStackFrame(
                allFrames: [SymbolisedStackFrame.SingleFrame(
                    address: stackFrame.instructionPointer,
                    functionName: "unknown @ 0x\(String(stackFrame.instructionPointer, radix: 16))",
                    functionOffset: 0,
                    library: "unknown-lib",
                    file: nil,
                    line: nil
                )]
            )
        }

        let relativeIP = stackFrame.instructionPointer - matched.fileMappedAddress
        self.logger.debug(
            "matched stackframe",
            metadata: [
                "matched": "\(matched)",
                "stack-frame": "\(stackFrame)",
                "relative-ip": "0x\(String(relativeIP, radix: 16))"
            ]
        )

        return try self.symbolizer.symbolise(relativeIP: relativeIP, library: matched, logger: self.logger)
    }

    public func symbolise(_ stackFrame: StackFrame) throws -> SymbolisedStackFrame {
        if let symd = self.cache[stackFrame.instructionPointer] {
            return symd
        } else {
            let symd = try self.symboliseSlow(stackFrame)
            self.cache[stackFrame.instructionPointer] = symd
            return symd
        }
    }

    @available(*, noasync, message: "blocks calling thread")
    public func renderPerfScriptFormat(_ sample: Sample) throws -> String {
        var output = ""
        output.reserveCapacity(256 + sample.stack.count * 128)

        output += """
                  \(sample.threadName)-T\(sample.tid)     \
                  \(sample.pid)/\(sample.tid)     \
                  \(sample.timeSec).\(sample.timeNSec):    \
                  swipr

                  """
        for stackFrame in sample.stack.dropFirst() {
            // We would have received the instruction pointer just _behind_ the actual instruction, so to accurately
            // get the right frame, we need to get the intruction prior. On ARM that's easy (subtract 4) but on Intel
            // that's impossible so we just subtract 1 instead.
            var fixedUpStackFrame = stackFrame
            if fixedUpStackFrame.instructionPointer >= 4 {
                #if arch(arm) || arch(arm64)
                // Known fixed-width instruction format
                fixedUpStackFrame.instructionPointer -= 4
                #else
                // Unknown, subtract 1
                fixedUpStackFrame.instructionPointer -= 1
                #endif
            }

            let framesIncludingInlinedFrames = try self.symbolise(fixedUpStackFrame).allFrames
            let hasMultiple = framesIncludingInlinedFrames.count > 1
            for index in framesIncludingInlinedFrames.indices {
                let symbolicatedFrame = framesIncludingInlinedFrames[index]
                let isLast = index == framesIncludingInlinedFrames.endIndex - 1

                output += """
                      \t    \
                      \(String(symbolicatedFrame.address, radix: 16)) \
                      \(symbolicatedFrame.functionName)\(hasMultiple && !isLast ? " [inlined]" :"")\
                      +0x\(String(symbolicatedFrame.functionOffset, radix: 16)) \
                      (\(symbolicatedFrame.library))

                      """
                if self.configuration.perfScriptOutputWithFileLineInformation,
                   let file = symbolicatedFrame.file, let line = symbolicatedFrame.line {
                    output += "  \(file):\(line)\n"
                }
            }
        }
        output += "\n"
        return output
    }

    public func shutdown() throws {
        try self.symbolizer.shutdown()
    }
}

@available(*, unavailable, message: "not thread safe")
extension CachedSymbolizer: Sendable {}

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

public struct SymbolisedStackFrame: Sendable & Hashable {
    public struct SingleFrame: Sendable & Hashable {
        public var address: UInt
        public var functionName: String
        public var functionOffset: UInt
        public var _library: Optional<String>
        public var vmap: Optional<DynamicLibMapping>
        public var file: Optional<String>
        public var line: Optional<Int>

        public var library: String {
            return self._library ?? self.vmap?.path ?? "unknown-lib"
        }

        public init(
            address: UInt,
            functionName: String,
            functionOffset: UInt,
            library: String?,
            vmap: DynamicLibMapping?,
            file: Optional<String> = nil,
            line: Optional<Int> = nil
        ) {
            self.address = address
            self.functionName = functionName
            self.functionOffset = functionOffset
            self._library = library
            self.vmap = vmap
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

    var description: String { get }
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
        func makeFailed(_ why: String = "") -> SymbolisedStackFrame {
            return SymbolisedStackFrame(
                allFrames: [SymbolisedStackFrame.SingleFrame(
                    address: relativeIP,
                    functionName: "unknown\(why) @ 0x\(String(relativeIP, radix: 16))",
                    functionOffset: 0,
                    library: nil,
                    vmap: library,
                    file: nil,
                    line: nil
                )]
            )
        }

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
            return makeFailed("-load-failed")
        }

        let results = elfImage.lookupRealAndInlinedFrames(address: UInt64(relativeIP), logger: logger)

        guard let results = results else {
            return makeFailed()
        }
        return SymbolisedStackFrame(
            allFrames: results.map { result in SymbolisedStackFrame.SingleFrame(
                address: relativeIP,
                functionName: result.name,
                functionOffset: UInt(exactly: result.offset) ?? 0,
                library: nil,
                vmap: library,
                file: nil,
                line: nil
            )
            }
        )
    }

    public func shutdown() throws {}

    public var description: String {
        return "NativeSymboliser(cachedELFs: \(self.elfSourceCache.count))"
    }
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
public class CachedSymbolizer: CustomStringConvertible {
    public let dynamicLibraryMappings: [DynamicLibMapping]
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
        self.dynamicLibraryMappings = dynamicLibraryMappings
            .compactMap { mapping in
                guard mapping.segmentStartAddress <= mapping.segmentEndAddress else {
                    logger.error(
                        "illegal dynamic library mapping (segment start > end), ignoring",
                        metadata: ["mapping": "\(mapping)"]
                    )
                    return nil
                }
                return mapping
            }.sorted(by: { l, r in
                return l.segmentStartAddress < r.segmentStartAddress
            })
        self.group = group
        self.symbolizer = symbolizer
        self.logger = logger
        logger.trace("starting CachedSymbolizer", metadata: ["mappings": "\(self.dynamicLibraryMappings)"])
        try self.symbolizer.start()
    }

    private func symboliseSlow(_ stackFrame: StackFrame) throws -> SymbolisedStackFrame {
        let matchedIndex = self.dynamicLibraryMappings.binarySearch { candidate in
            if stackFrame.instructionPointer < candidate.segmentStartAddress {
                return .candidateIsTooHigh
            } else if stackFrame.instructionPointer >= candidate.segmentEndAddress {
                return .candidateIsTooLow
            } else {
                assert(
                    stackFrame.instructionPointer >= candidate.segmentStartAddress &&
                    stackFrame.instructionPointer <= candidate.segmentEndAddress
                )
                return .found
            }
        }
        let matched = matchedIndex.map { self.dynamicLibraryMappings[$0] }

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
            } else {
                assert(allMatched.first == matched, "\(allMatched.debugDescription) != \(matched.debugDescription)")
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
                    library: nil,
                    vmap: nil,
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
        defer {
            if self.cache.count > 16_000 {
                self.cache.removeAll(keepingCapacity: true)
            }
        }
        if let symd = self.cache[stackFrame.instructionPointer] {
            return symd
        } else {
            let symd = try self.symboliseSlow(stackFrame)
            self.cache[stackFrame.instructionPointer] = symd
            return symd
        }
    }

    public func shutdown() throws {
        try self.symbolizer.shutdown()
    }

    public var description: String {
        return "CachedSymbolizer(cache: \(self.cache.count), vmaps: \(self.dynamicLibraryMappings.count), sym: \(self.symbolizer.description))"
    }
}

@available(*, unavailable, message: "not thread safe")
extension CachedSymbolizer: Sendable {}

internal enum BinarySearchOrder {
    case candidateIsTooLow
    case found
    case candidateIsTooHigh
}

extension RandomAccessCollection {
    internal func binarySearch(_ compare: (Element) -> BinarySearchOrder) -> Self.Index? {
        var lo: Index = self.startIndex
        var hi: Index = self.index(before: self.endIndex)

        while true {
            let distance = self.distance(from: lo, to: hi)
            guard distance >= 0 else { break }

            // Compute the middle index of this iteration's search range.
            let mid = self.index(lo, offsetBy: distance / 2)
            assert(self.distance(from: self.startIndex, to: mid) >= 0)
            assert(self.distance(from: mid, to: self.endIndex) > 0)

            // If there is a match, return the result.
            let cmp = compare(self[mid])
            switch cmp {
            case .found:
                return mid
            case .candidateIsTooHigh:
                hi = self.index(before: mid)
            case .candidateIsTooLow:
                lo = self.index(after: mid)
            }
        }

        // Check exit conditions of the binary search.
        assert(self.distance(from: self.startIndex, to: lo) >= 0)
        assert(self.distance(from: lo, to: self.endIndex) >= 0)

        return nil
    }
}

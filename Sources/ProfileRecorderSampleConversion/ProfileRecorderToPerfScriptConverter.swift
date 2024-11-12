//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import Logging
import Foundation

public struct ProfileRecorderToPerfScriptConverter: Sendable {
    let symbolizerConfiguration: SymbolizerConfiguration
    let threadPool: NIOThreadPool
    let group: EventLoopGroup
    let makeSymbolizer: @Sendable ([DynamicLibMapping]) throws -> any Symbolizer

    public struct Error: Swift.Error {
        var message: String
    }

    public init(
        config: SymbolizerConfiguration,
        threadPool: NIOThreadPool = .singleton,
        group: any EventLoopGroup = .singletonMultiThreadedEventLoopGroup,
        makeSymbolizer: @Sendable @escaping ([DynamicLibMapping]) throws -> any Symbolizer
    ) {
        self.symbolizerConfiguration = config
        self.makeSymbolizer = makeSymbolizer
        self.threadPool = threadPool
        self.group = group
    }

    public func convert(
        inputRawProfileRecorderFormat fromPath: String,
        outputPerfScriptFormat toPath: String,
        logger: Logger
    ) async throws {
        return try await self.threadPool.runIfActive {
            try self.convertSync(inputRawProfileRecorderFormat: fromPath, outputPerfScriptFormat: toPath, logger: logger)
        }
    }

    @available(*, noasync, message: "blocks calling thread")
    public func convertSync(
        inputRawProfileRecorderFormat fromPath: String,
        outputPerfScriptFormat toPath: String,
        logger: Logger
    ) throws {
        let input = fromPath == "-" ? stdin : fopen(fromPath, "r")
        guard let input = input else {
            throw Error(message: "Could not open \(fromPath), errno: \(errno)")
        }
        defer {
            if fromPath != "-" {
                fclose(input)
            }
        }
        let output = toPath == "-" ? stdout: fopen(toPath, "w")
        guard let output = output else {
            throw Error(message: "Could not open \(toPath), errno: \(errno)")
        }
        defer {
            if toPath != "-" {
                fclose(output)
            }
        }
        let decoder = JSONDecoder()

        var symboliser: CachedSymbolizer? = nil
        defer {
            try! symboliser?.shutdown()
        }
        var vmaps: [DynamicLibMapping] = []
        var vmapsRead = true
        var currentSample: Sample? = nil
        var bufferCapacity: ssize_t = 1024
        var buffer: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer<CChar>.allocate(capacity: Int(bufferCapacity))
        defer {
            buffer?.deallocate()
        }

        while getline(&buffer, &bufferCapacity, input) != -1 {
            let line = String(cString: buffer!)
            guard line.starts(with: "[SWIPR] ") else {
                continue
            }
            switch line.dropFirst(8).prefix(4) {
            case "MESG":
                guard let message = try? decoder.decode(Message.self, from: Data(line.dropFirst(13).utf8)) else {
                    continue
                }
                logger.info("\(message.message)")
                if let _ = message.exit {
                    throw Error(message: message.message)
                }
            case "VERS":
                guard let version = try? decoder.decode(Version.self, from: Data(line.dropFirst(13).utf8)) else {
                    logger.error("Could not decode Swift Profile Recorder version", metadata: ["line": "\(line)"])
                    throw Error(message: "Could not decode Swift Profile Recorder version in '\(line)'")
                }
                guard version.version == 1 else {
                    logger.error(
                        "This is a Swift Profile Recorder trace of the wrong version, but we're only compatible with version 1",
                        metadata: ["trace-version": "\(version.version)", "our-version": "1"]
                    )
                    throw Error(message: "Can only decode Swift Profile Recorder version 1 traces, this is \(version.version)")
                }
            case "VMAP":
                guard let mapping = try? decoder.decode(DynamicLibMapping.self, from: Data(line.dropFirst(13).utf8)) else {
                    continue
                }

                if vmapsRead {
                    try symboliser?.shutdown()
                    symboliser = nil
                    vmaps.removeAll()
                    vmapsRead = false
                }
                vmaps.append(mapping)
            case "SMPL":
                vmapsRead = true
                if symboliser == nil {
                    let underlyingSymboliser: any Symbolizer = try self.makeSymbolizer(vmaps)

                    symboliser = try CachedSymbolizer(
                        configuration: .default,
                        symbolizer: underlyingSymboliser,
                        dynamicLibraryMappings: vmaps,
                        group: group,
                        logger: logger
                    )
                }
                guard let header = try? decoder.decode(SampleHeader.self, from: Data(line.dropFirst(13).utf8)) else {
                    logger.warning("failed to parse line, ignoring", metadata: ["line": "\(line.dropFirst(13)))"])
                    continue
                }

                currentSample = Sample(sampleHeader: header, stack: [])
            case "STCK":
                guard let stackFrame = try? decoder.decode(StackFrame.self, from: Data(line.dropFirst(13).utf8)) else {
                    continue
                }
                currentSample?.stack.append(stackFrame)
            case "DONE":
                if let sample = currentSample, let symboliser = symboliser {
                    fputs(try symboliser.renderPerfScriptFormat(sample), output)
                }
            default:
                logger.warning("unknown line, ignoring", metadata: ["line": "\(line.dropFirst(8).prefix(4)))"])
                continue
            }
        }
    }
}

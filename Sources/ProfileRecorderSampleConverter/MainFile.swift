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


import Foundation
import NIO
import Logging

@main
struct Main {
    static func main() {
        var logger = Logger(label: "swipr-sample-conv")
        logger.logLevel = .info
        do {
            try Self.go(logger: logger)
        } catch {
            fputs("ERROR: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    static func go(logger: Logger) throws {
        let appVersion = "1.0"

        if CommandLine.arguments.count == 2 && (CommandLine.arguments[1] == "--version" || CommandLine.arguments[1] == "-v") {
            print(appVersion)
            exit(EX_OK)
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try! group.syncShutdownGracefully()
        }

        let decoder = JSONDecoder()

        var symboliser: Symboliser? = nil
        defer {
            try! symboliser?.shutdown()
        }
        var vmaps: [DynamicLibMapping] = []
        var vmapsRead = true
        var currentSample: Sample? = nil

        while let line = readLine() {
            guard line.starts(with: "[SWIPR] ") else {
                continue
            }
            switch line.dropFirst(8).prefix(4) {
            case "MESG":
                guard let message = try? decoder.decode(Message.self, from: Data(line.dropFirst(13).utf8)) else {
                    continue
                }
                logger.info("\(message.message)")
                if let exitCode = message.exit {
                    exit(exitCode)
                }
            case "VERS":
                guard let version = try? decoder.decode(Version.self, from: Data(line.dropFirst(13).utf8)) else {
                    logger.error("Could not decode Swift Profile Recorder version", metadata: ["line": "\(line)"])
                    exit(EXIT_FAILURE)
                }
                guard version.version == 1 else {
                    logger.error(
                        "This is a Swift Profile Recorder trace of the wrong version, but we're only compatible with version 1",
                        metadata: ["trace-version": "\(version.version)", "our-version": "1"]
                    )
                    exit(EXIT_FAILURE)
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
                    symboliser = try Symboliser(
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
                    try processModern(sample, symboliser: symboliser)
                }
            default:
                logger.warning("unknown line, ignoring", metadata: ["line": "\(line.dropFirst(8).prefix(4)))"])
                continue
            }
        }
    }
}

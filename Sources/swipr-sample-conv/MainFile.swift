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

import ArgumentParser

import Foundation
import NIO
import Logging
import ProfileRecorderSampleConversion

@main
struct ProfileRecorderSampleConverter: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swipr-sample-conv",
        version: EmbeddedAppVersion().description
    )

    @Option(help: "Use llvm-symbolizer's JSON format instead of the text format?")
    var viaJSON: Bool = false

    @Option(help: "Use the native symboliser?")
    var useNativeSymbolizer: Bool = false

    @Option(help: "Enable the llvm-symbolizer getting stuck workaround?")
    var unstuckerWorkaround: Bool = false

    @Option(help: "Should we attempt to print file:line information?")
    var enableFileLine: Bool = false

    @Option(help: "Log level to use", transform: { stringValue in
        return try Logger.Level(rawValue: stringValue) ?? {
            throw ValidationError("unknown log level \(stringValue)")
        }()
    })
    var logLevel: Logger.Level = .info

    @Option(name: [.customLong("debug-sym")], help: "Debugging, feed FILE:ADDRESS pairs into the symboliser")
    var debugSymbolication: [String] = []

    func run() async throws {
        var logger = Logger(label: "swipr-sample-conv")
        logger.logLevel = self.logLevel

        guard self.debugSymbolication.isEmpty else {
            try self.runDebugSymbolication(self.debugSymbolication, logger: logger)
            return
        }

        do {
            try await Self.go(
                useNativeSymbolizer: self.useNativeSymbolizer,
                llvmSymboliserConfig: LLVMSymboliserConfig(
                    viaJSON: self.viaJSON,
                    unstuckerWorkaround: self.unstuckerWorkaround
                ),
                printFileLine: self.enableFileLine,
                logger: logger
            )
        } catch {
            fputs("ERROR: \(error)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    static func go(
        useNativeSymbolizer: Bool,
        llvmSymboliserConfig: LLVMSymboliserConfig,
        printFileLine: Bool,
        logger: Logger
    ) async throws {
        var config = SymbolizerConfiguration.default
        config.perfScriptOutputWithFileLineInformation = printFileLine
        let converter = ProfileRecorderToPerfScriptConverter(
            config: config,
            makeSymbolizer: { vmaps in
                if useNativeSymbolizer {
                    return NativeSymboliser(dynamicLibraryMappings: vmaps)
                } else {
                    return LLVMSymboliser(
                        config: llvmSymboliserConfig,
                        dynamicLibraryMappings: vmaps,
                        group: .singletonMultiThreadedEventLoopGroup,
                        logger: logger
                    )
                }
            }
        )

        try await converter.convert(inputRawProfileRecorderFormat: "-", outputPerfScriptFormat: "-", logger: logger)
    }

    func runDebugSymbolication(_ syms: [String], logger: Logger) throws {
        let fileAddresses: [(String, UInt?)] = syms.map { fileAddressString -> (String, UInt?) in
            let split = fileAddressString.split(separator: ":")
            guard split.count == 2 else {
                return ("<could not parse: \(fileAddressString)>", nil)
            }
            guard let address = UInt(hexDigits: String(split[1])) else {
                return ("<could not parse address: \(split[1])>", nil)
            }
            return (String(split[0]), address)
        }

        for fileAddress in fileAddresses {
            guard let address = fileAddress.1 else {
                print(fileAddress.0)
                continue
            }
            let symboliser = NativeSymboliser(
                dynamicLibraryMappings: [DynamicLibMapping(
                    path: fileAddress.0,
                    fileMappedAddress: 0,
                    segmentStartAddress: 0,
                    segmentEndAddress: .max
                )]
            )
            try symboliser.start()
            defer {
                try! symboliser.shutdown()
            }
            let symd = try symboliser.symbolise(
                StackFrame(
                    instructionPointer: address,
                    stackPointer: 0
                ),
                logger: logger
            )
            print(fileAddress.0, "0x\(String(address, radix: 16))", symd)
        }
    }
}

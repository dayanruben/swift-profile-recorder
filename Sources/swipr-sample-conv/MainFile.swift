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
struct ProfileRecorderSampleConverterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swipr-sample-conv",
        version: EmbeddedAppVersion().description
    )

    @Option(help: "Use llvm-symbolizer's JSON format instead of the text format?")
    var viaJSON: Bool = false

    @Option(help: "Use the fake symboliser?")
    var useFakeSymbolizer: Bool = false

    @Option(help: "Use the native symboliser?")
    var useNativeSymbolizer: Bool = true

    @Option(help: "Enable the llvm-symbolizer getting stuck workaround?")
    var unstuckerWorkaround: Bool = false

    @Option(help: "Should we attempt to print file:line information?")
    var enableFileLine: Bool = false

    @Option(help: "Which output format", transform: { stringValue in
        switch stringValue {
        case "perf-script":
            return .perfSymbolized
        case "pprof":
            return .pprofSymbolized
        case "raw":
            return .raw
        default:
            throw ValidationError("unknown format '\(stringValue)', try 'perf-script' or 'pprof'")
        }
    })
    var format: ProfileRecorderOutputFormat = .perfSymbolized

    @Option(help: "Log level to use", transform: { stringValue in
        return try Logger.Level(rawValue: stringValue) ?? {
            throw ValidationError("unknown log level \(stringValue)")
        }()
    })
    var logLevel: Logger.Level = .info

    @Option(name: [.customLong("debug-sym")], help: "Debugging, feed FILE:ADDRESS pairs into the symboliser")
    var debugSymbolication: [String] = []

    @Option(name: [.customLong("output"), .customShort("o")], help: "Where to write to?")
    var outputPath: String = "-"

    @Argument(help: "Input file path (in raw Swift Profile Recorder format)")
    var inputPath: String = "-"

    func run() async throws {
        var logger = Logger(label: "swipr-sample-conv")
        logger.logLevel = self.logLevel

        let llvmSymbolizerConfig = LLVMSymboliserConfig(
            viaJSON: self.viaJSON,
            unstuckerWorkaround: self.unstuckerWorkaround
        )
        guard self.debugSymbolication.isEmpty else {
            try Self.runDebugSymbolication(
                self.debugSymbolication,
                logger: logger,
                llvmSymbolizerConfig: llvmSymbolizerConfig,
                useNativeSymbolizer: self.useNativeSymbolizer
            )
            return
        }

        do {
            let renderer: any ProfileRecorderSampleConversionOutputRenderer
            switch self.format {
            case .perfSymbolized:
                renderer = PerfScriptOutputRenderer()
            case .pprofSymbolized:
                renderer = PprofOutputRenderer()
            case .raw:
                throw ValidationError("the input file is already in raw format")
            }
            try await Self.go(
                inputPath: self.inputPath,
                outputPath: self.outputPath,
                useNativeSymbolizer: self.useNativeSymbolizer,
                useFakeSymbolizer: self.useFakeSymbolizer,
                llvmSymboliserConfig: llvmSymbolizerConfig,
                printFileLine: self.enableFileLine,
                renderer: renderer,
                logger: logger
            )
        } catch {
            fputs("ERROR: \(error)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    static func go(
        inputPath: String,
        outputPath: String,
        useNativeSymbolizer: Bool,
        useFakeSymbolizer: Bool,
        llvmSymboliserConfig: LLVMSymboliserConfig,
        printFileLine: Bool,
        renderer: any ProfileRecorderSampleConversionOutputRenderer,
        logger: Logger
    ) async throws {
        var config = SymbolizerConfiguration.default
        config.perfScriptOutputWithFileLineInformation = printFileLine
        let converter = ProfileRecorderSampleConverter(
            config: config,
            renderer: renderer,
            makeSymbolizer: {
                if useFakeSymbolizer {
                    return FakeSymbolizer()
                }
                if useNativeSymbolizer {
                    return NativeSymboliser()
                } else {
                    return LLVMSymboliser(
                        config: llvmSymboliserConfig,
                        group: .singletonMultiThreadedEventLoopGroup,
                        logger: logger
                    )
                }
            }
        )

        try await converter.convert(
            inputRawProfileRecorderFormatPath: inputPath,
            outputPath: outputPath,
            format: .perfSymbolized,
            logger: logger
        )
    }

    static func runDebugSymbolication(
        _ syms: [String],
        logger: Logger,
        llvmSymbolizerConfig: LLVMSymboliserConfig,
        useNativeSymbolizer: Bool
    ) throws {
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

        let symboliser: any Symbolizer = useNativeSymbolizer ? NativeSymboliser() : LLVMSymboliser(
            config: llvmSymbolizerConfig,
            group: .singletonMultiThreadedEventLoopGroup,
            logger: logger
        )
        try symboliser.start()
        defer {
            try! symboliser.shutdown()
        }

        for fileAddress in fileAddresses {
            guard let address = fileAddress.1 else {
                print(fileAddress.0)
                continue
            }
            let symd = try symboliser.symbolise(
                relativeIP: address,
                library: DynamicLibMapping(
                    path: fileAddress.0,
                    fileMappedAddress: 0,
                    segmentStartAddress: 0,
                    segmentEndAddress: .max
                ),
                logger: logger
            )
            print(fileAddress.0, "0x\(String(address, radix: 16))", symd)
        }
    }
}

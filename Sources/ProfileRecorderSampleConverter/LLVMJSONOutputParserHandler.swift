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
import NIOFoundationCompat
import Foundation

// {"Address":"0x8acec","ModuleName":"/lib/libc6-prof/aarch64-linux-gnu/libc.so.6","Symbol":[{"Column":7,"Discriminator":0,"FileName":"./malloc/./malloc/malloc.c","FunctionName":"sysmalloc_mmap","Line":2485,"StartAddress":"0x8ac60","StartFileName":"./malloc/./malloc/malloc.c","StartLine":2420}]}
// {"Address":"0xffffffffffffffff","Error":{"Message":"No such file or directory"},"ModuleName":"/ignore/errors/about/this"}
// {"Address":"0xffffffffffffffff","ModuleName":"/ignore/errors/about/this","Symbol":[]}
struct LLVMSymbolizerJSONOutput: Codable & Sendable {
    struct GoodSymbol: Sendable {
        var functionName: String
        var offset: UInt
        var sourceFile: Optional<String>
        var sourceLine: Optional<Int>
    }

    struct Symbol: Codable & Sendable {
        var Column: Int?
        var Discriminator: Int?
        var FileName: String?
        var FunctionName: String?
        var Line: Int?
        var StartAddress: String?
        var StartFileName: String?
        var StartLine: Int?

        func goodSymbol(address: String) -> GoodSymbol? {
            guard let functionName = self.FunctionName else { return nil }

            let maybeAddress = UInt(hexDigits: address)
            let maybeStartAddress = UInt(hexDigits: self.StartAddress ?? address) ?? maybeAddress
            let offset: UInt
            if let address = maybeAddress, let startAddress = maybeStartAddress, address >= startAddress {
                offset = address - startAddress
            } else {
                offset = 0
            }

            return GoodSymbol(
                functionName: functionName.isEmpty ? "<unknown in \(self.FileName.flatMap { $0.isEmpty ? nil : $0 } ?? "empty")>": functionName,
                offset: offset,
                sourceFile: (self.FileName?.isEmpty ?? true) ? nil : self.FileName,
                sourceLine: self.Line
            )
        }
    }
    struct Error: Codable & Sendable {
        var Message: String?
    }
    var Address: String?
    var ModuleName: String?
    var Symbol: [Symbol]?
    var Error: Error?
}

final internal class LLVMJSONOutputParserHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = SymbolisedStackFrame

    private var accumulation: [ByteBuffer] = []
    private let jsonDecoder = JSONDecoder()

    struct CouldNotParseOutputError: Error {
        init(output: ByteBuffer) {
            self.output = String(buffer: output)
        }

        var output: String
    }

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = Self.unwrapInboundIn(data)
        do {
            let decoded = try self.jsonDecoder.decode(LLVMSymbolizerJSONOutput.self, from: data)
            guard let address = decoded.Address else {
                context.fireErrorCaught(CouldNotParseOutputError(output: data))
                return
            }
            guard let symbolList = decoded.Symbol, !symbolList.isEmpty else {
                context.fireChannelRead(
                    Self.wrapInboundOut(
                        SymbolisedStackFrame(
                            allFrames: [SymbolisedStackFrame.SingleFrame(
                                address: address,
                                functionName: "<unknown-unset>",
                                functionOffset: 0,
                                library: decoded.ModuleName ?? "unknown-library",
                                file: nil,
                                line: nil
                            )]
                        )
                    )
                )
                return
            }

            let hasMultiple = symbolList.count > 1
            var outputFrames: [SymbolisedStackFrame.SingleFrame] = []
            for index in symbolList.indices {
                let symbol = symbolList[index]
                let isLast = index == symbolList.endIndex - 1

                var output = SymbolisedStackFrame.SingleFrame(
                    address: address,
                    functionName: "<unknown-unset>",
                    functionOffset: 0,
                    library: decoded.ModuleName ?? "unknown-unset",
                    file: nil,
                    line: nil
                )

                if let goodSymbol = symbol.goodSymbol(address: address) {
                    output.functionName = goodSymbol.functionName
                    output.functionOffset = goodSymbol.offset
                    output.line = goodSymbol.sourceLine
                    output.file = goodSymbol.sourceFile
                }

                if hasMultiple && !isLast {
                    output.functionName += " [inlined]"
                }
                outputFrames.append(output)
            }
            context.fireChannelRead(Self.wrapInboundOut(SymbolisedStackFrame(allFrames: outputFrames)))
        } catch {
            context.fireErrorCaught(error)
        }
    }
}

extension Optional {
    mutating func setIfNonNil(_ newValue: Wrapped?) {
        guard let newValue = newValue else {
            return
        }
        self = newValue
    }
}

extension UInt {
    init?(hexDigits: String) {
        let result: Self?
        if hexDigits.hasPrefix("0x") {
            result = Self(hexDigits.dropFirst(2), radix: 16)
        } else {
            result = Self(hexDigits)
        }
        guard let result = result else {
            return nil
        }
        self = result
    }
}

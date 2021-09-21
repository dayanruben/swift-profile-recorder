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

final internal class LLVMOutputParserHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = String

    private var accumulation: [ByteBuffer] = []

    private struct CouldNotParseOutputError: Error {
        init(output: [ByteBuffer]) {
            self.output = output.map { String(buffer: $0) }
        }

        var output: [String]
    }

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = self.unwrapInboundIn(data)

        if data.readableBytes == 0 {
            // done, process now

            if self.accumulation.count < 3 {
                context.fireErrorCaught(CouldNotParseOutputError(output: self.accumulation))
                self.accumulation.removeAll()
            } else {
                let out = "\(String(buffer: self.accumulation[0])) \(String(buffer: self.accumulation[1]))+0x0 (somewhere)"
                self.accumulation.removeAll()
                context.fireChannelRead(self.wrapInboundOut(out))
            }
        } else {
            if self.accumulation.isEmpty && String(buffer: data).starts(with: "CODE ") {
                let address = String(String(buffer: data).dropFirst(5))
                context.fireChannelRead(self.wrapInboundOut("\(address) \(address) (somewhere)"))
            } else {
                self.accumulation.append(data)
            }
        }
    }
}

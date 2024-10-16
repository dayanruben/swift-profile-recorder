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
import Foundation

final internal class LLVMStackFrameEncoderHandler: ChannelOutboundHandler {
    typealias OutboundIn = StackFrame
    typealias OutboundOut = ByteBuffer

    private let dynamicLibraryMappings: [DynamicLibMapping]
    private let fileManager: FileManager

    internal init(dynamicLibraryMappings: [DynamicLibMapping]) {
        self.dynamicLibraryMappings = dynamicLibraryMappings
        self.fileManager = FileManager.default
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let stackFrame = Self.unwrapOutboundIn(data)

        var buffer = context.channel.allocator.buffer(capacity: 256)

        let matched = self.dynamicLibraryMappings.filter { mapping in
            stackFrame.instructionPointer >= mapping.segmentStartAddress &&
            stackFrame.instructionPointer < mapping.segmentEndAddress
        }.first

        if let matched = matched, self.fileManager.fileExists(atPath: matched.path) {
            buffer.writeString("\"")
            buffer.writeString(matched.path)
            buffer.writeString("\" 0x")
            buffer.writeString(String(stackFrame.instructionPointer - matched.fileMappedAddress, radix: 16))
        } else {
            buffer.writeString("/ignore/errors/about/this 0x")
            buffer.writeString(String(stackFrame.instructionPointer, radix: 16))
        }
        buffer.writeString("\n")
        context.write(Self.wrapOutboundOut(buffer), promise: promise)
    }
}

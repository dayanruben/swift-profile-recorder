//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2022-2025 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import Foundation

public struct DynamicLibMapping: Decodable, CustomStringConvertible {
    enum CodingKeys: CodingKey {
        case path
        case fileMappedAddress
        case segmentStartAddress
        case segmentEndAddress
    }
    public var path: String
    public var fileMappedAddress: UInt
    public var segmentStartAddress: UInt
    public var segmentEndAddress: UInt

    public init(from decoder: Decoder) throws {
        struct FailedToDecodeAddressError: Error {}

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        if let fileMappedAddress = UInt(try container.decode(String.self, forKey: .fileMappedAddress).dropFirst(2), radix: 16) {
            self.fileMappedAddress = fileMappedAddress
        } else {
            throw FailedToDecodeAddressError()
        }
        if let startAddress = UInt(try container.decode(String.self, forKey: .segmentStartAddress).dropFirst(2), radix: 16) {
            self.segmentStartAddress = startAddress
        } else {
            throw FailedToDecodeAddressError()
        }
        if let endAddress = UInt(try container.decode(String.self, forKey: .segmentEndAddress).dropFirst(2), radix: 16) {
            self.segmentEndAddress = endAddress
        } else {
            throw FailedToDecodeAddressError()
        }
    }

    public var description: String {
        return """
               DynamicLibMapping {\
                path: '\(self.path)',\
                start: 0x\(String(self.segmentStartAddress, radix: 16)),\
                end: 0x\(String(self.segmentEndAddress, radix: 16))\
               }
               """
    }
}

public struct SampleHeader: Codable {
    var pid: Int
    var tid: Int
    var timeSec: Int
    var timeNSec: Int
}

public struct StackFrame: Codable, CustomStringConvertible, Hashable {
    public enum CodingKeys: String, CodingKey {
        case instructionPointer = "ip"
        case stackPointer = "sp"
    }
    public var instructionPointer: UInt
    public var stackPointer: UInt

    public init(from decoder: Decoder) throws {
        struct FailedToDecodeAddressError: Error {}

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let ip = UInt(try container.decode(String.self, forKey: .instructionPointer).dropFirst(2), radix: 16) {
            self.instructionPointer = ip
        } else {
            throw FailedToDecodeAddressError()
        }
        if let sp = UInt(try container.decode(String.self, forKey: .stackPointer).dropFirst(2), radix: 16) {
            self.stackPointer = sp
        } else {
            throw FailedToDecodeAddressError()
        }
    }

    public var description: String {
        return """
               StackFrame {\
                ip: 0x\(String(self.instructionPointer, radix: 16)),\
                sp: 0x\(String(self.stackPointer, radix: 16))\
               }
               """
    }
}

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

func symboliserInput(_ sample: Sample, _ dynamicLibs: [DynamicLibMapping], into symbolizerInput: inout String) throws {
    for stackFrame in sample.stack {
        let matchedLibs = dynamicLibs.filter { mapping in
            stackFrame.instructionPointer >= mapping.segmentStartAddress &&
            stackFrame.instructionPointer < mapping.segmentEndAddress
        }

        //print("MATCH ", stackFrame, matchedLibs)

        let matchedLib = matchedLibs.first

        let path: String
        let address: UInt

        if let lib = matchedLib {
            path = lib.path+" "
            address = stackFrame.instructionPointer - lib.fileMappedAddress
        } else {
            path = ""
            address = stackFrame.instructionPointer
        }

        symbolizerInput += "\(path)0x\(String(address, radix: 16))\n"
    }
}

func processAll(_ samples: [Sample], _ dynamicLibs: [DynamicLibMapping]) throws {
    var symbolizerInput = ""

    for sample in samples {
        try symboliserInput(sample, dynamicLibs, into: &symbolizerInput)
    }

    try symbolize(symbolizerInput, samples: samples)
}

func symbolize(_ input: String, samples: [Sample]) throws {
    let dir = NSTemporaryDirectory() + "\(UUID())"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false)
    defer {
        //try! FileManager.default.removeItem(atPath: dir)
    }

    let inputURL = URL(fileURLWithPath: "\(dir)/input")
    let outputURL = URL(fileURLWithPath: "\(dir)/output")
    try Data(input.utf8).write(to: inputURL)
    try Data().write(to: outputURL)

    let p = Process()
    p.standardInput = try FileHandle(forReadingFrom: inputURL)
    p.standardOutput = try FileHandle(forWritingTo: outputURL)
    p.executableURL = URL(fileURLWithPath: "/usr/bin/llvm-symbolizer")
    p.arguments = ["--use-symbol-table=true", "--print-address", "--demangle=1", "--inlining=true", "--functions=linkage", "--color=1"]
    try p.run()
    p.waitUntilExit()

    var index = 0
    for sample in samples {
        print("\(sample.threadName == "" ? "unknown" : sample.threadName)_\(sample.tid)     \(sample.pid)/\(sample.tid)     \(sample.timeSec).\(sample.timeNSec):    1001001 cpu-clock:pppH:")
        let lines = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self).components(separatedBy: "\n")
        for _ in 0..<sample.stack.count {
            print("\t \(lines[index*4]) \(lines[index*4 + 1])+0x0 (the_lib)")
            index += 1
        }
        print()
    }
}

func process(_ sample: Sample, _ dynamicLibs: [DynamicLibMapping]) throws {
    var symbolizerInput = ""

    try symboliserInput(sample, dynamicLibs, into: &symbolizerInput)
    try symbolize(symbolizerInput, samples: [sample])
}

func processModern(_ sample: Sample, symboliser: Symboliser) throws {
    print("\(sample.threadName)-T\(sample.tid)     \(sample.pid)/\(sample.tid)     \(sample.timeSec).\(sample.timeNSec):    1001001 cpu-clock:pppH:")
    for stackFrame in sample.stack {
        print("\t \(try symboliser.symbolise(stackFrame))")
    }
    print()
}

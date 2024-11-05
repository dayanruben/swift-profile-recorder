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
import ProfileRecorder
import Dispatch

@main
struct Main {
    static func main() throws {
        ProfileRecorderSampler.sharedInstance.requestSamples(
            outputFilePath: "-",
            count: 10,
            timeBetweenSamples: .milliseconds(
                3
            ),
            queue: DispatchQueue.global(),
            { result in
                print("- collected samples")
            }
        )

        print("STARTING to burn CPU")
        for _ in 0..<200 {
            burnCPU()
        }
        print("DONE burning CPU")
    }
}

func burnCPU() {
    // CPU-expensive (or blocking) function
    #if DEBUG
    let notRotated = Array(1...400)
    #else
    let notRotated = Array(1...10_000)
    #endif
    var rotated = notRotated
    rotated.rotate(toStartAt: 1)

    while notRotated != rotated {
        rotated.rotate(toStartAt: 1)
    }
}

extension Array {
    mutating func rotate(toStartAt index: Int) {
        let tmp = self[0..<index]
        self[0...] = self[index...]
        self.append(contentsOf: tmp)
    }
}

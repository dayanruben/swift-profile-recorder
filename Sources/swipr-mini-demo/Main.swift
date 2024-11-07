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

import ArgumentParser
import ProfileRecorder
import Dispatch
import Foundation

@main
struct ProfileRecorderMiniDemo: ParsableCommand {
    @Option(help: "Should we run a blocking function?")
    var blocking: Bool = false

    @Option(help: "Should we burn a bit of CPU?")
    var burnCPU: Bool = true

    @Option(help: "Should we burn do a bunch of Array.appends?")
    var arrayAppends: Bool = false

    @Option(help: "How many samples?")
    var sampleCount: Int = 100

    @Option(help: "How many ms between samples?")
    var msBetweenSamples: Int64 = 10

    @Option(help: "Where to write the samples to?")
    var output: String = "-"

    @Option(help: "How many iterations?")
    var iterations: Int = 10

    func run() throws {
        ProfileRecorderSampler.sharedInstance.requestSamples(
            outputFilePath: self.output,
            failIfFileExists: false,
            count: self.sampleCount,
            timeBetweenSamples: .milliseconds(
                self.msBetweenSamples
            ),
            queue: DispatchQueue.global(),
            { result in
                print("- collected samples: \(result)")
            }
        )

        print("""
              STARTING to \(self.iterations) iterations \
              \(self.burnCPU ? ", burn CPU" : "") \
              \(self.arrayAppends ? ", array appends" : "") \
              \(self.blocking ? ", blocking" : "")
              """
        )
        for _ in 0..<self.iterations {
            if self.arrayAppends {
                var xs: [Int] = []
                for x in 0..<4_000_000 {
                    xs.append(x)
                }
                precondition(xs.count == xs.count - 1 + 1)
            }
            if self.burnCPU {
                doBurnCPU()
            }
            if self.blocking {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        print("DONE")
    }
}

func doBurnCPU() {
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

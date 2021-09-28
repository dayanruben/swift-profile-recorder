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

import ProfileRecorder
import NIO
import Foundation
import Dispatch

let signalQueue = DispatchQueue(label: "swipr-signal-queue")
let signalSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: signalQueue)
signalSource.setEventHandler {
    ProfileRecorderSampler.sharedInstance.requestSamples(outputFilePath: "/tmp/samples_\(getpid())_\(Date().timeIntervalSince1970)",
                                               failIfFileExists: true,
                                               count: 100,
                                               timeBetweenSamples: .milliseconds(10),
                                               queue: signalQueue) { result in
        switch result {
        case .success(let file):
            print("\(Date()): Samples successfully written to \(file).")
        case .failure(let error):
            print("\(Date()): Sampling failed: \(error).")
        }
    }
}
signal(SIGUSR1, SIG_IGN)
signalSource.resume()

runWebServer()

signalSource.cancel()

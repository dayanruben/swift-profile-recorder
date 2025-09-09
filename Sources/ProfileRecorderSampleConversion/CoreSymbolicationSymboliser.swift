//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
import Logging
import NIOConcurrencyHelpers

public final class CoreSymbolicationSymboliser: Symbolizer & Sendable {

    private let cache: NIOLockedValueBox<[String: CSSymbolicatorRef]> = NIOLockedValueBox([:])
    
    public init() {}

    public func start() throws {}
    
    public func symbolise(
        relativeIP: UInt, // the offset to the instruction WITHOUT bass address
        library: DynamicLibMapping,
        logger: Logging.Logger
    ) throws -> SymbolisedStackFrame {
        
        func makeFailed(_ why: String = "") -> SymbolisedStackFrame {
            return SymbolisedStackFrame(
                allFrames: [SymbolisedStackFrame.SingleFrame(
                    address: relativeIP,
                    functionName: "unknown-missing\(why) @ 0x\(String(relativeIP, radix: 16))",
                    functionOffset: 0,
                    library: nil,
                    vmap: library,
                    file: nil,
                    line: nil
                )]
            )
        }
        
        let symbolicator = self.cache.withLockedValue { cache in
            let sym = {
                if (cache[library.path] != nil) {
                    return cache[library.path]!
                } else {
                    // TODO: refactor out symbolicator creation, reacquire the lock, and then store into cache
                    let symbolicator = SymbolicatorCreateWithDynamicLibMapping(library)
                    if cache.count > 1_000 {
                        let old = cache.remove(at: cache.startIndex)
                        CSRelease(old.value)
                    }
                    cache[library.path] = symbolicator
                    return symbolicator
                }
            }()
            return CSRetain(sym) // in case another thread releases sym
        }
        
        defer {
            CSRelease(symbolicator)
        }
        
        if CSIsNull(symbolicator){
            return makeFailed("-symbolicator")
        }
        
        let symbolOwner = CSSymbolicatorGetSymbolOwner(symbolicator)
        if CSIsNull(symbolOwner){
            return makeFailed("-symbolOwner")
        }

        // CS expects offset into library + base address from CS
        let baseAddress = CSSymbolOwnerGetBaseAddress(symbolOwner)
        let expectedIP = vm_address_t(relativeIP
                                      + library.fileMappedAddress
                                      - library.segmentStartAddress) + baseAddress

        let symbol = CSSymbolicatorGetSymbolWithAddressAtTime(symbolicator, expectedIP)
        if CSIsNull(symbol){
            return makeFailed("-symbol")
        }
        let name = CSSymbolGetName(symbol) ?? "unknown"

        return SymbolisedStackFrame(
            allFrames: [SymbolisedStackFrame.SingleFrame(
                address: expectedIP,
                functionName: name,
                functionOffset: relativeIP,
                library: nil,
                vmap: library,
                file: nil,
                line: nil
            )]
        )
    }
    
    public func shutdown() throws {
        let allSyms = self.cache.withLockedValue { cache in
            let allValues = cache.values
            cache.removeAll()
            return allValues
        }
        for syms in allSyms {
            CSRelease(syms)
        }
    }
    
    public var description: String {
        return "CoreSymbolicationSymboliser"
    }
}
#endif

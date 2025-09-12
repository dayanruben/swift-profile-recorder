//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
// This file has been adjusted for ProfileRecorder, originally of the Swift.org open source project
// - Removed Crash Reporter related code
// - Added functions to Sym:
//      - CSSymbolicatorGetSymbolWithAddressAtTime,
//      - CSSymbolicatorCreateWithPathAndArchitecture,
//      - CSSymbolicatorGetSymbolOwner
//===--- CoreSymbolication.swift - Shims for CoreSymbolication ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// CoreSymbolication is a private framework, which makes it tricky to link
// with from here and also means there are no headers on customer builds.
//
//===----------------------------------------------------------------------===//

#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin
import Foundation
import CProfileRecorderSwiftELF

// .. Dynamic binding ..........................................................
private let coreFoundationPath =
  "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"

private let coreFoundationHandle = dlopen(coreFoundationPath, RTLD_LAZY)!

private let coreSymbolicationPath =
  "/System/Library/PrivateFrameworks/CoreSymbolication.framework/CoreSymbolication"
private let coreSymbolicationHandle = dlopen(coreSymbolicationPath, RTLD_LAZY)!

private func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T {
  guard let result = dlsym(handle, name) else {
    fatalError("Unable to look up \(name) in CoreSymbolication")
  }
  return unsafeBitCast(result, to: T.self)
}

// Define UniChar
typealias UniChar = UInt16
typealias CSTypeRef = CProfileRecorderSwiftELF.CSTypeRef
typealias CSBinaryImageInformation = CProfileRecorderSwiftELF.CSBinaryImageInformation
typealias CSNotificationBlock = CProfileRecorderSwiftELF.CSNotificationBlock
typealias CSSymbolicatorRef = CProfileRecorderSwiftELF.CSSymbolicatorRef
typealias CFUUIDBytes = CProfileRecorderSwiftELF.CFUUIDBytes
 
private enum Sym {
    // Base functionality
    static let CSRetain: @convention(c) (CSTypeRef) -> CSTypeRef =
    symbol(coreSymbolicationHandle, "CSRetain")
    static let CSRelease: @convention(c) (CSTypeRef) -> () =
      symbol(coreSymbolicationHandle, "CSRelease")
    static let CSEqual: @convention(c) (CSTypeRef, CSTypeRef) -> CBool =
      symbol(coreSymbolicationHandle, "CSEqual")
    static let CSIsNull: @convention(c) (CSTypeRef) -> CBool =
      symbol(coreSymbolicationHandle, "CSIsNull")
    static let CSArchitectureGetArchitectureForName:
    @convention(c) (UnsafePointer<CChar>) -> CSArchitecture =
    symbol(coreSymbolicationHandle, "CSArchitectureGetArchitectureForName")
    
    // CSSymbolicator
    static let CSSymbolicatorCreateWithBinaryImageList:
      @convention(c) (UnsafeMutablePointer<CSBinaryImageInformation>,
                      UInt32, UInt32, CSNotificationBlock?) -> CSSymbolicatorRef =
      symbol(coreSymbolicationHandle, "CSSymbolicatorCreateWithBinaryImageList")
    static let CSSymbolicatorGetSymbolOwnerWithAddressAtTime:
      @convention(c) (CSSymbolicatorRef, vm_address_t,
                      CSMachineTime) -> CSSymbolOwnerRef =
      symbol(coreSymbolicationHandle, "CSSymbolicatorGetSymbolOwnerWithAddressAtTime")
    static let CSSymbolicatorForeachSymbolOwnerAtTime:
      @convention(c) (CSSymbolicatorRef, CSMachineTime, @convention(block) (CSSymbolOwnerRef) -> Void) -> UInt =
        symbol(coreSymbolicationHandle, "CSSymbolicatorForeachSymbolOwnerAtTime")
    static let CSSymbolicatorGetSymbolOwner:
      @convention(c) (CSSymbolicatorRef) -> CSSymbolOwnerRef =
        symbol(coreSymbolicationHandle, "CSSymbolicatorGetSymbolOwner")
    static let CSSymbolicatorGetSymbolWithAddressAtTime:
      @convention(c) (CSSymbolicatorRef, vm_address_t, CSMachineTime) -> CSSymbolRef =
        symbol(coreSymbolicationHandle, "CSSymbolicatorGetSymbolWithAddressAtTime")
    static let CSSymbolicatorCreateWithPathAndArchitecture:
    @convention(c) (UnsafePointer<CChar>, CSArchitecture) -> CSSymbolicatorRef =
    symbol(coreSymbolicationHandle, "CSSymbolicatorCreateWithPathAndArchitecture")
    
    // CSSymbolOwner
    static let CSSymbolOwnerGetName:
      @convention(c) (CSSymbolOwnerRef) -> UnsafePointer<CChar>? =
      symbol(coreSymbolicationHandle, "CSSymbolOwnerGetName")
    static let CSSymbolOwnerGetSymbolWithAddress:
      @convention(c) (CSSymbolOwnerRef, vm_address_t) -> CSSymbolRef =
      symbol(coreSymbolicationHandle, "CSSymbolOwnerGetSymbolWithAddress")
    static let CSSymbolOwnerGetSourceInfoWithAddress:
      @convention(c) (CSSymbolOwnerRef, vm_address_t) -> CSSourceInfoRef =
      symbol(coreSymbolicationHandle, "CSSymbolOwnerGetSourceInfoWithAddress")
    static let CSSymbolOwnerForEachStackFrameAtAddress:
      @convention(c) (CSSymbolOwnerRef, vm_address_t, CSStackFrameIterator) -> UInt =
      symbol(coreSymbolicationHandle, "CSSymbolOwnerForEachStackFrameAtAddress")
    static let CSSymbolOwnerGetBaseAddress:
      @convention(c) (CSSymbolOwnerRef) -> vm_address_t =
      symbol(coreSymbolicationHandle, "CSSymbolOwnerGetBaseAddress")
    
    // CSSymbol
    static let CSSymbolGetRange:
      @convention(c) (CSSymbolRef) -> CSRange =
      symbol(coreSymbolicationHandle, "CSSymbolGetRange")
    static let CSSymbolGetName:
      @convention(c) (CSSymbolRef) -> UnsafePointer<CChar>? =
      symbol(coreSymbolicationHandle, "CSSymbolGetName")
    static let CSSymbolGetMangledName:
      @convention(c) (CSSymbolRef) -> UnsafePointer<CChar>? =
      symbol(coreSymbolicationHandle, "CSSymbolGetMangledName")

    // CSSourceInfo
    static let CSSourceInfoGetPath:
      @convention(c) (CSSourceInfoRef) -> UnsafePointer<CChar>? =
      symbol(coreSymbolicationHandle, "CSSourceInfoGetPath")
    static let CSSourceInfoGetLineNumber:
      @convention(c) (CSSourceInfoRef) -> UInt32 =
      symbol(coreSymbolicationHandle, "CSSourceInfoGetLineNumber")
    static let CSSourceInfoGetColumn:
      @convention(c) (CSSourceInfoRef) -> UInt32 =
      symbol(coreSymbolicationHandle, "CSSourceInfoGetColumn")

    // CFString
    static let CFStringCreateWithBytes:
      @convention(c) (CFAllocator?, UnsafeRawPointer?, CFIndex,
                      CFStringEncoding, Bool) -> CFString? =
      symbol(coreFoundationHandle, "CFStringCreateWithBytes")
    static let CFStringGetLength:
      @convention(c) (CFString) -> CFIndex =
      symbol(coreFoundationHandle, "CFStringGetLength")
    static let CFStringGetCStringPtr:
      @convention(c) (CFString, CFStringEncoding) -> UnsafePointer<CChar>? =
      symbol(coreFoundationHandle, "CFStringGetCStringPtr")
    static let CFStringGetBytes:
      @convention(c) (CFString, CFRange, CFStringEncoding, UInt8, Bool,
                      UnsafeMutableRawPointer?, CFIndex,
                      UnsafeMutablePointer<CFIndex>?) -> CFIndex =
      symbol(coreFoundationHandle, "CFStringGetBytes")
    static let CFStringGetCharactersPtr:
      @convention(c) (CFString) -> UnsafePointer<UniChar>? =
      symbol(coreFoundationHandle, "CFStringGetCharactersPtr")
}

internal func CFRangeMake(_ location: CFIndex, _ length: CFIndex) -> CFRange {
  return CFRange(location: location, length: length)
}

internal func CFStringCreateWithBytes(_ allocator: CFAllocator?,
                                      _ bytes: UnsafeRawPointer?,
                                      _ length: CFIndex,
                                      _ encoding: CFStringEncoding,
                                      _ isExternalRepresentation: Bool)
  -> CFString? {
  return Sym.CFStringCreateWithBytes(allocator,
                                     bytes,
                                     length,
                                     encoding,
                                     isExternalRepresentation)
}

internal func CFStringGetLength(_ s: CFString) -> CFIndex {
  return Sym.CFStringGetLength(s)
}

internal func CFStringGetCStringPtr(_ s: CFString,
                                    _ encoding: CFStringEncoding)
  -> UnsafePointer<CChar>? {
  return Sym.CFStringGetCStringPtr(s, encoding)
}

internal func CFStringGetCharactersPtr(_ s: CFString)
  -> UnsafePointer<UniChar>? {
  return Sym.CFStringGetCharactersPtr(s);
}

internal func CFStringGetBytes(_ s: CFString,
                               _ range: CFRange,
                               _ encoding: CFStringEncoding,
                               _ lossByte: UInt8,
                               _ isExternalRepresentation: Bool,
                               _ buffer: UnsafeMutableRawPointer?,
                               _ maxBufLen: CFIndex,
                               _ usedBufLen: UnsafeMutablePointer<CFIndex>?)
  -> CFIndex {
  return Sym.CFStringGetBytes(s, range, encoding, lossByte,
                              isExternalRepresentation, buffer, maxBufLen,
                              usedBufLen)
}

// .. Base functionality .......................................................

func CSRetain(_ obj: CSTypeRef) -> CSTypeRef {
  return Sym.CSRetain(obj)
}

func CSRelease(_ obj: CSTypeRef) {
  Sym.CSRelease(obj)
}

func CSEqual(_ a: CSTypeRef, _ b: CSTypeRef) -> Bool {
  return Sym.CSEqual(a, b)
}

func CSIsNull(_ obj: CSTypeRef) -> Bool {
  return Sym.CSIsNull(obj)
}

// .. CSSymbolicator ...........................................................

let kCSSymbolicatorDisallowDaemonCommunication = UInt32(0x00000800)

struct BinaryRelocationInformation {
  var base: vm_address_t
  var extent: vm_address_t
  var name: String
}

struct BinaryImageInformation {
  var base: vm_address_t
  var extent: vm_address_t
  var uuid: CFUUIDBytes
  var arch: CSArchitecture
  var path: String
  var relocations: [BinaryRelocationInformation]
  var flags: UInt32
}

func SymbolicatorCreateWithDynamicLibMapping(
    _ library: DynamicLibMapping
) -> CSSymbolicatorRef
{
    return library.path.withCString { path in
        library.architecture.withCString { arch in
            let CSarch = Sym.CSArchitectureGetArchitectureForName(arch)
            return Sym.CSSymbolicatorCreateWithPathAndArchitecture(path, CSarch)
        }
    }
}

func CSSymbolicatorGetSymbolOwnerWithAddress(
  _ symbolicator: CSSymbolicatorRef,
  _ addr: vm_address_t
) -> CSSymbolOwnerRef {
  return Sym.CSSymbolicatorGetSymbolOwnerWithAddressAtTime(symbolicator,
                                                           addr, kCSBeginningOfTime)
}

func CSSymbolicatorForeachSymbolOwnerAtTime(
  _ symbolicator: CSSymbolicatorRef,
  _ time: CSMachineTime,
  _ symbolIterator: (CSSymbolOwnerRef) -> Void
  ) ->  UInt {
      return Sym.CSSymbolicatorForeachSymbolOwnerAtTime(symbolicator, time,
                                                        symbolIterator)
}

func CSSymbolicatorGetSymbolOwner(
    _ symbolicator: CSSymbolicatorRef
) -> CSSymbolOwnerRef {
    var owner: CSSymbolOwnerRef = kCSNull
    
    let count = CSSymbolicatorForeachSymbolOwnerAtTime(symbolicator, kCSAllTimes) { symbolOwner in
        owner = symbolOwner
    }
    
    if count == 1 {
        return owner
    }
    
    return kCSNull
}

func CSSymbolicatorGetSymbolWithAddressAtTime(
  _ symbolicator: CSSymbolicatorRef,
  _ address: vm_address_t
  ) ->  CSSymbolRef {
      return Sym.CSSymbolicatorGetSymbolWithAddressAtTime(symbolicator, address, kCSBeginningOfTime)
}

// .. CSSymbolOwner ............................................................

func CSSymbolOwnerGetName(_ sym: CSTypeRef) -> String? {
  Sym.CSSymbolOwnerGetName(sym)
    .map(String.init(cString:))
}

func CSSymbolOwnerGetSymbolWithAddress(
  _ owner: CSSymbolOwnerRef,
  _ address: vm_address_t
) -> CSSymbolRef {
  return Sym.CSSymbolOwnerGetSymbolWithAddress(owner, address)
}

func CSSymbolOwnerGetSourceInfoWithAddress(
  _ owner: CSSymbolOwnerRef,
  _ address: vm_address_t
) -> CSSourceInfoRef {
  return Sym.CSSymbolOwnerGetSourceInfoWithAddress(owner, address)
}

func CSSymbolOwnerForEachStackFrameAtAddress(
  _ owner: CSSymbolOwnerRef,
  _ address: vm_address_t,
  _ iterator: CSStackFrameIterator
) -> UInt {
  return Sym.CSSymbolOwnerForEachStackFrameAtAddress(owner, address, iterator)
}

func CSSymbolOwnerGetBaseAddress(
  _ owner: CSSymbolOwnerRef
) -> vm_address_t {
  return Sym.CSSymbolOwnerGetBaseAddress(owner)
}

// .. CSSymbol .................................................................
func CSSymbolGetName(_ symbol: CSSymbolRef) -> String? {
  return Sym.CSSymbolGetName(symbol).map{ String(cString: $0) }
}

#endif


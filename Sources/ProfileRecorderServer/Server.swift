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

import NIO
import NIOHTTP1
import ProfileRecorder
import _NIOFileSystem
import Foundation
import NIOFoundationCompat
import Logging

public struct ProfileRecorderServerConfiguration: Sendable {
    public var group: MultiThreadedEventLoopGroup
    public var bindTarget: Optional<SocketAddress>
    internal var unixDomainSocketPath: Optional<String>

    /// Check the environment variable `SWIPR_SAMPLING_SERVER_URL` for the URL.
    public static func parseFromEnvironment() async throws -> Self {
        let serverURLString: String

        if let string = ProcessInfo.processInfo.environment["SWIPR_SAMPLING_SERVER_URL"] {
            serverURLString = string
        } else if let string = ProcessInfo.processInfo.environment["SWIPR_SAMPLING_SERVER_URL_PATTERN"] {
            serverURLString = string
                .replacingOccurrences(of: "{PID}", with: "\(getpid())")
                .replacingOccurrences(of: "{UUID}", with: "\(UUID().uuidString)")
        } else {
            return Self(group: .singleton, bindTarget: nil, unixDomainSocketPath: nil)
        }
        let serverURL = URL(string: serverURLString)
        let bindTarget: SocketAddress
        switch serverURL?.scheme {
        case "http":
            bindTarget = try SocketAddress.makeAddressResolvingHost(
                serverURL?.host ?? "127.0.0.1",
                port: serverURL?.port ?? 0
            )
        case "http+unix":
            guard let path = serverURL?.host?.removingPercentEncoding, path.count > 0 else {
                throw ProfileRecorderServer.Error(message: "need UNIX Domain Socket path in host for \(serverURLString)")
            }
            bindTarget = try SocketAddress(unixDomainSocketPath: path)
        case "unix":
            guard let path = serverURL?.path.removingPercentEncoding, path.count > 0 else {
                throw ProfileRecorderServer.Error(message: "need UNIX Domain Socket path in path for \(serverURLString)")
            }
            bindTarget = try SocketAddress(unixDomainSocketPath: path)
        default:
            throw ProfileRecorderServer.Error(message: "unsupported scheme in \(serverURLString)")
        }

        return Self(group: .singleton, bindTarget: bindTarget, unixDomainSocketPath: nil)
    }
}

public struct ProfileRecorderServer: Sendable {
    public let configuration: ProfileRecorderServerConfiguration

    public struct Error: Swift.Error {
        var message: String
    }

    public struct ServerInfo: Sendable {
        public enum ServerStartResult: Sendable {
            case notAttemptedToStartSamplingServer
            case successful(SocketAddress)
            case couldNotStart(any Swift.Error)
        }
        public var startResult: ServerStartResult
    }

    public init(configuration: ProfileRecorderServerConfiguration) {
        self.configuration = configuration
    }

    public func run(logger: Logger) async throws {
        try await self.withSamplingServer(logger: logger) { info in
            switch info.startResult {
            case .couldNotStart(let error):
                logger.warning("could not start Swift Profile Recorder sampling server", metadata: ["error": "\(error)"])
                throw error
            case .notAttemptedToStartSamplingServer:
                logger.debug(
                    "ProfileRecorder sampling server start not requested via SWIPR_SAMPLING_SERVER_URL env var",
                    metadata: ["example": "SWIPR_SAMPLING_SERVER_URL=http://127.0.0.1:12345"]
                )
                return
            case .successful:
                ()
            }
            logger.info("ProfileRecorder sampling server running", metadata: ["info": "\(info)"])
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    public func withSamplingServer<R: Sendable>(
        logger: Logger,
        _ body: @Sendable @escaping (ServerInfo) async throws -> R
    ) async throws -> R {
        guard let bindTarget = self.configuration.bindTarget else {
            return try await body(ServerInfo(startResult: .notAttemptedToStartSamplingServer))
        }
        let serverChannel: NIOAsyncChannel<NIOAsyncChannel<NIOHTTPServerRequestFull, HTTPPart<HTTPResponseHead, ByteBuffer>>, Never>
        do {
            serverChannel = try await ServerBootstrap(group: self.configuration.group)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .bind(
                    to: bindTarget,
                    childChannelInitializer: { channel in
                        do {
                            try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                            try channel.pipeline.syncOperations.addHandlers(
                                NIOHTTPServerRequestAggregator(maxContentLength: 1024),
                                HTTPByteBufferResponsePartHandler()
                            )
                            return channel.eventLoop.makeSucceededFuture(
                                try NIOAsyncChannel<NIOHTTPServerRequestFull, HTTPPart<HTTPResponseHead, ByteBuffer>>(
                                    wrappingChannelSynchronously: channel
                                )
                            )
                        } catch {
                            return channel.eventLoop.makeFailedFuture(error)
                        }
                    })
        } catch {
            logger.info("failed to bind Swift Profile Recorder sampling server", metadata: ["error": "\(error)"])
            return try await (body(ServerInfo(startResult: .couldNotStart(error))))
        }

        return try await asyncDo {
            return try await serverChannel.executeThenClose { server in
                return try await withThrowingTaskGroup(of: R?.self) { group in
                    group.addTask {
                        return try await body(ServerInfo(startResult: .successful(serverChannel.channel.localAddress!)))
                    }
                    group.addTask {
                        await withTaskGroup(of: Void.self) { childGroup in
                            do {
                                for try await child in server {
                                    childGroup.addTask {
                                        var logger = logger
                                        logger[metadataKey: "peer"] = "\(child.channel.remoteAddress!)"
                                        do {
                                            logger.info("ProfileRecorder sampling server connection received")
                                            try await child.executeThenClose {
                                                inbound,
                                                outbound in
                                                for try await request in inbound {
                                                    logger.info(
                                                        "ProfileRecorder sampling server request",
                                                        metadata: ["request": "\(request)"]
                                                    )
                                                    try await handleRequest(request, outbound: outbound, logger: logger)
                                                }
                                                outbound.finish()
                                            }
                                        } catch {
                                            logger.info(
                                                "failure whilst handling samples",
                                                metadata: ["error": "\(error)"]
                                            )
                                        }
                                    }
                                }
                                await childGroup.waitForAll()
                            } catch {
                                logger.debug(
                                    "ProfileRecorder sampling server failure or cancellation",
                                    metadata: ["error": "\(error)"]
                                )
                                guard error is CancellationError else {
                                    logger.info(
                                        "ProfileRecorder sampling server failure",
                                        metadata: ["error": "\(error)"]
                                    )
                                    return
                                }
                            }
                        }
                        return nil
                    }
                    defer {
                        group.cancelAll()
                    }
                    while let result = try await group.next() {
                        if let actualResult = result {
                            return actualResult
                        } else {
                            continue
                        }
                    }
                    fatalError("unreachable")
                }
            }
        } finally: {
            if let udsPath = configuration.unixDomainSocketPath {
                _ = try? await FileSystem.shared.removeItem(at: FilePath(udsPath))
            }
        }
    }

    func respondWithFailure(
        string: String,
        code: HTTPResponseStatus,
        _ outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>
    ) async throws {
        try await outbound.write(.head(HTTPResponseHead(version: .http1_1, status: code)))
        try await outbound.write(.body(ByteBuffer(string: string)))
        try await outbound.write(.body(ByteBuffer(string: "\n")))
        try await outbound.write(.end(nil))
    }

    func handleRequest(
        _ request: NIOHTTPServerRequestFull,
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        logger: Logger
    ) async throws {
        guard request.head.method == .POST else {
            let example = SampleRequest(
                numberOfSamples: 100,
                timeInterval: TimeAmount.milliseconds(100),
                format: .perfSymbolized
            )
            let exampleEncoded = String(decoding: try! JSONEncoder().encode(example), as: UTF8.self)
            let exampleURL: String
            var exampleCURLArgs: [String] = []
            let bindTarget = self.configuration.bindTarget!  // will work, we received a request on it!
            switch bindTarget {
            case .v4:
                let ipAddress = bindTarget.ipAddress!  // IPv4 has IP addresses
                guard ipAddress != "0.0.0.0" else {
                    exampleURL = "http://127.0.0.1:\(bindTarget.port!)/sample"
                    break
                }
                exampleURL = "http://\(ipAddress):\(bindTarget.port!)/sample"
            case .v6:
                let ipAddress = bindTarget.ipAddress!  // IPv6 has IP addresses
                guard ipAddress != "::" else {
                    exampleURL = "http://[::1]:\(bindTarget.port!)/sample"
                    break
                }
                exampleURL = "http://\(ipAddress):\(bindTarget.port!)/sample"
            case .unixDomainSocket:
                let udsPath = bindTarget.pathname!
                exampleURL = "http+unix://\(udsPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)/sample"
                exampleCURLArgs.append(contentsOf: ["--unix-socket", udsPath, "http://127.0.0.1/sample"])
            }

            if exampleCURLArgs.isEmpty {
                exampleCURLArgs.append(contentsOf: [exampleURL])
            }
            exampleCURLArgs.insert(contentsOf: ["-s", "-d", "'"+exampleEncoded+"'"], at: 0)
            try await self.respondWithFailure(
                string: """
                        Welcome to the Swift Profile Recorder Server!

                        To request samples, please send POST request to \(exampleURL)

                        Example body: \(exampleEncoded)

                        If you're using curl, you could run

                          curl \(exampleCURLArgs.joined(separator: " ")) > /tmp/samples

                        To also immediately demangle the symbols, run

                          curl \(exampleCURLArgs.joined(separator: " ")) | swift demangle --simplified > /tmp/samples

                        """,
                code: .badRequest,
                outbound
            )
            return
        }
        let sampleRequest: SampleRequest
        do {
            sampleRequest = try JSONDecoder().decode(SampleRequest.self, from: request.body ?? ByteBuffer())
            try await ProfileRecorderSampler.sharedInstance._withSamples(
                sampleCount: sampleRequest.numberOfSamples,
                timeBetweenSamples: sampleRequest.timeInterval,
                format: sampleRequest.format,
                logger: logger
            ) { samples in
                try await outbound.write(
                    .head(
                        HTTPResponseHead(
                            version: .http1_1,
                            status: .ok,
                            headers: [
                                "content-disposition": "filename=\"samples-\(getpid())-\(time(nil)).perf\"",
                                "content-type": "application/octet-stream",
                            ]
                        )
                    )
                )
                try await FileSystem.shared.withFileHandle(forReadingAt: FilePath(samples)) { handle in
                    var reader = handle.bufferedReader()
                    while true {
                        let chunk = try await reader.read(.mebibytes(4))
                        guard chunk.readableBytes > 0 else { break }
                        try await outbound.write(.body(chunk))
                    }
                }
                try await outbound.write(.end(nil))
            }
        } catch {
            try await self.respondWithFailure(string: "\(error)", code: .internalServerError, outbound)
            return
        }
    }
}

struct SampleRequest: Sendable & Codable {
    var numberOfSamples: Int
    var timeInterval: TimeAmount
    var format: ProfileRecorderSampler._SampleFormat

    typealias SampleFormat = ProfileRecorderSampler._SampleFormat

    private enum CodingKeys: CodingKey {
        case numberOfSamples
        case timeInterval
        case format
    }

    internal init(numberOfSamples: Int, timeInterval: TimeAmount, format: SampleFormat) {
        self.numberOfSamples = numberOfSamples
        self.timeInterval = timeInterval
        self.format = format
    }

    init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<SampleRequest.CodingKeys> = try decoder.container(keyedBy: SampleRequest.CodingKeys.self)
        
        self.numberOfSamples = try container.decode(Int.self, forKey: SampleRequest.CodingKeys.numberOfSamples)
        let timeIntervalString = try container.decode(String.self, forKey: SampleRequest.CodingKeys.timeInterval)
        self.timeInterval = try TimeAmount(timeIntervalString, defaultUnit: "ms")
        self.format = try container.decodeIfPresent(SampleFormat.self, forKey: .format) ?? .perfSymbolized
    }
    
    func encode(to encoder: any Encoder) throws {
        var container: KeyedEncodingContainer<SampleRequest.CodingKeys> = encoder.container(keyedBy: SampleRequest.CodingKeys.self)
        
        try container.encode(self.numberOfSamples, forKey: SampleRequest.CodingKeys.numberOfSamples)
        try container.encode(self.timeInterval.prettyPrint, forKey: SampleRequest.CodingKeys.timeInterval)
        if self.format != .perfSymbolized {
            try container.encode(self.format, forKey: .format)
        }
    }
}

final class HTTPByteBufferResponsePartHandler: ChannelOutboundHandler {
    typealias OutboundIn = HTTPPart<HTTPResponseHead, ByteBuffer>
    typealias OutboundOut = HTTPServerResponsePart

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let part = self.unwrapOutboundIn(data)
        switch part {
        case .head(let head):
            context.write(self.wrapOutboundOut(.head(head)), promise: promise)
        case .body(let buffer):
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: promise)
        case .end(let trailers):
            context.write(self.wrapOutboundOut(.end(trailers)), promise: promise)
        }
    }
}

struct TimeAmountConversionError: Error {
    var message: String
}


extension TimeAmount {
    init(_ userProvidedString: String, defaultUnit: String) throws {
        let string = String(userProvidedString.filter { !$0.isWhitespace }).lowercased()
        let parsedNumbers = string.prefix(while: { $0.isWholeNumber || $0.isPunctuation })
        let parsedUnit = string.dropFirst(parsedNumbers.count)

        guard let numbers = Int64(parsedNumbers) else {
            throw TimeAmountConversionError(message: "'\(userProvidedString)' cannot be parsed as number and unit")
        }
        let unit = parsedUnit.isEmpty ? defaultUnit : String(parsedUnit)

        switch unit {
        case "h", "hr":
            self = .hours(numbers)
        case "min":
            self = .minutes(numbers)
        case "s":
            self = .seconds(numbers)
        case "ms":
            self = .milliseconds(numbers)
        case "us":
            self = .microseconds(numbers)
        case "ns":
            self = .nanoseconds(numbers)
        default:
            throw TimeAmountConversionError(message: "Unknown unit '\(unit)' in '\(userProvidedString)")
        }
    }

    var prettyPrint: String {
        let fullNS = self.nanoseconds
        let (fullUS, remUS) = fullNS.quotientAndRemainder(dividingBy: 1_000)
        let (fullMS, remMS) = fullNS.quotientAndRemainder(dividingBy: 1_000_000)
        let (fullS, remS) = fullNS.quotientAndRemainder(dividingBy: 1_000_000_000)

        if remS == 0 {
            return "\(fullS) s"
        } else if remMS == 0 {
            return "\(fullMS) ms"
        } else if remUS == 0 {
            return "\(fullUS) us"
        } else {
            return "\(fullNS) ns"
        }
    }
}

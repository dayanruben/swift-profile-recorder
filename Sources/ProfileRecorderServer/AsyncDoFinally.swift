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
/// Runs `body` and when body returns or throws, run `finally`.
///
/// This is useful as an async version of this code pattern
///
/// ```swift
/// let resource = try createResource()
/// defer {
///     try? destroyResource()
/// }
/// return try useResource()
/// ```
///
/// - note: Even if the task that `asyncDo` is running is is cancelled, the `finally` code will run in a task that
///         is _not_ cancelled. This is crucial to not require all cleanup code to work in an already-cancelled task.
@inlinable
public func asyncDo<R: Sendable>(
    returning: R.Type = R.self,
    _ body: @Sendable () async throws -> R,
    finally: @escaping @Sendable () async throws -> Void
) async throws -> R {
    try await asyncDo {
        try await body()
    } finally: { _ in
        try await finally()
    }
}

/// Runs `body` and when body returns or throws, run `finally`.
///
/// This is useful as an async version of this code pattern
///
/// ```swift
/// let resource = try createResource()
/// defer {
///     try? destroyResource()
/// }
/// return try useResource()
/// ```
///
/// - note: Even if the task that `asyncDo` is running is is cancelled, the `finally` code will run in a task that
///         is _not_ cancelled. This is crucial to not require all cleanup code to work in an already-cancelled task.
@inlinable
public func asyncDo<R: Sendable>(
    returning: R.Type = R.self,
    _ body: @Sendable () async throws -> R,
    finally: @escaping @Sendable (Error?) async throws -> Void
) async throws -> R {
    let result: R
    do {
        result = try await body()
    } catch {
        try? await withUncancelledTask {
            try await finally(error)
        }
        throw error
    }

    try await withUncancelledTask {
        try await finally(nil)
    }
    return result
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/**
 - Parameters:
    - customError: The failure returned by this closure is thrown when the operation timeouts.
    If `customError` is `nil`, then `CancellationError` is thrown.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func withTimeout<Success: Sendable>(
    _ duration: ContinuousClock.Duration,
    tolerance: ContinuousClock.Duration? = nil,
    customError: (@Sendable () -> Error)? = nil,
    operation: @Sendable () async throws -> Success
) async throws -> Success {
    let clock = ContinuousClock()
    return try await withDeadline(after: clock.now.advanced(by: duration), tolerance: tolerance, clock: clock, customError: customError, operation: operation)
}

#if compiler(<6.1)
/**
 - Parameters:
    - customError: The failure returned by this closure is thrown when the operation timeouts.
    If `customError` is `nil`, then `CancellationError` is thrown.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func withTimeout<C: Clock, Success: Sendable>(
    _ duration: C.Duration,
    tolerance: C.Duration? = nil,
    clock: C,
    customError: (@Sendable () -> Error)? = nil,
    operation: @Sendable () async throws -> Success
) async throws -> Success {
    try await withDeadline(after: clock.now.advanced(by: duration), tolerance: tolerance, clock: clock, customError: customError, operation: operation)
}
#endif

/**
 - Parameters:
    - customError: The failure returned by this closure is thrown when the operation timeouts.
    If `customError` is `nil`, then `CancellationError` is thrown.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func withTimeout<Success: Sendable>(
    _ duration: Duration,
    tolerance: Duration? = nil,
    clock: any Clock<Duration>,
    customError: (@Sendable () -> Error)? = nil,
    operation: @Sendable () async throws -> Success
) async throws -> Success {
    try await withoutActuallyEscaping(operation) { operation in
        try await race(operation) {
            try await clock.sleep(for: duration, tolerance: tolerance)
            throw customError?() ?? CancellationError()
        }.unsafelyUnwrapped
    }
}

/**
 - Parameters:
    - customError: The failure returned by this closure is thrown when the operation timeouts.
    If `customError` is `nil`, then `CancellationError` is thrown.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func withDeadline<Success: Sendable>(
    after instant: ContinuousClock.Instant,
    tolerance: ContinuousClock.Duration? = nil,
    customError: (@Sendable () -> Error)? = nil,
    operation: @Sendable () async throws -> Success
) async throws -> Success {
    try await withDeadline(after: instant, tolerance: tolerance, clock: .continuous, customError: customError, operation: operation)
}

/**
 - Parameters:
    - customError: The failure returned by this closure is thrown when the operation timeouts.
    If `customError` is `nil`, then `CancellationError` is thrown.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func withDeadline<C: Clock, Success: Sendable>(
    after instant: C.Instant,
    tolerance: C.Duration? = nil,
    clock: C,
    customError: (@Sendable () -> Error)? = nil,
    operation: @Sendable () async throws -> Success
) async throws -> Success {
    try await withoutActuallyEscaping(operation) { operation in
        try await race(operation) {
            try await clock.sleep(until: instant, tolerance: tolerance)
            throw customError?() ?? CancellationError()
        }.unsafelyUnwrapped
    }
}

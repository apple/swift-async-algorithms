//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// An error that wraps an underlying error when an operation times out.
public struct TimeoutError<UnderylingError: Error>: Error {
  /// The error thrown by the timed-out operation.
  public var underlying: UnderylingError

  /// Creates a timeout error with the specified underlying error.
  ///
  /// - Parameter underlying: The error thrown by the operation that timed out.
  public init(underlying: UnderylingError) {
    self.underlying = underlying
  }
}

/// Executes an asynchronous operation with a specified timeout duration.
///
/// Use this function to limit the execution time of an asynchronous operation. If the operation
/// completes before the timeout expires, this function returns the result. If the timeout expires
/// first, this function cancels the operation and throws a ``TimeoutError``.
///
/// The following example demonstrates using a timeout to limit a network request:
///
/// ```swift
/// do {
///     let result = try await withTimeout(in: .seconds(5)) {
///         try await fetchDataFromServer()
///     }
///     print("Data received: \(result)")
/// } catch let error as TimeoutError<NetworkError> {
///     print("Request timed out: \(error.underlying)")
/// }
/// ```
///
/// - Important: This function cancels the operation when the timeout expires, but waits for the operation
/// to return. The function may run longer than the specified timeout duration if the operation doesn't respond
/// to cancellation immediately.
///
/// - Parameters:
///   - timeout: The maximum duration to wait for the operation to complete.
///   - tolerance: The tolerance used for the sleep.
///   - clock: The clock to use for measuring time. The default is `ContinuousClock()`.
///   - body: The asynchronous operation to execute within the timeout period.
///
/// - Returns: The result of the operation if it completes before the timeout expires.
///
/// - Throws: A ``TimeoutError`` containing the underlying error if the operation throws or times out.
#if compiler(>=6.3)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) public func withTimeout<Return, Failure: Error, Clock: _Concurrency.Clock>(
  in timeout: Clock.Instant.Duration,
  tolerance: Clock.Instant.Duration? = nil,
  clock: Clock = .continuous,
  body: nonisolated(nonsending) () async throws(Failure) -> Return
) async throws(TimeoutError<Failure>) -> Return {
  nonisolated(unsafe) let body = body
  return try await _withTimeout(
    in: timeout,
    tolerance: tolerance,
    clock: clock
  ) { () async throws(Failure) -> Return in
    try await body()
  }
}
#elseif compiler(>=6.2)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) public func withTimeout<Return, Failure: Error, Clock: _Concurrency.Clock>(
  in timeout: Clock.Instant.Duration,
  tolerance: Clock.Instant.Duration? = nil,
  clock: Clock,
  body: nonisolated(nonsending) () async throws(Failure) -> Return
) async throws(TimeoutError<Failure>) -> Return {
  nonisolated(unsafe) let body = body
  return try await _withTimeout(
    in: timeout,
    tolerance: tolerance,
    clock: clock
  ) { () async throws(Failure) -> Return in
    try await body()
  }
}
#endif

#if compiler(>=6.2)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) public func _withTimeout<Return, Failure: Error, Clock: _Concurrency.Clock>(
  in timeout: Clock.Duration,
  tolerance: Clock.Instant.Duration?,
  clock: Clock,
  body: @Sendable () async throws(Failure) -> Return
) async throws(TimeoutError<Failure>) -> Return {
  try await withoutActuallyEscaping(body) { (escapingBody) async throws(TimeoutError<Failure>) -> Return in
    var t = Optional(escapingBody)
    return try await __withTimeout(in: timeout, tolerance: tolerance, clock: clock, body: &t)
  }
}

private enum TaskResult<Return: Sendable, Failure: Error>: Sendable {
  case success(Return)
  case error(Failure)
  case timedOut
  case cancelled
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) public func __withTimeout<Return, Failure: Error, Clock: _Concurrency.Clock>(
  in timeout: Clock.Duration,
  tolerance: Clock.Instant.Duration?,
  clock: Clock,
  body: inout (@Sendable () async throws(Failure) -> Return)?
) async throws(TimeoutError<Failure>) -> Return {
  let result: Result<Disconnected<Return>, TimeoutError<Failure>> = await withTaskGroup(
    of: TaskResult<Disconnected<Return>, Failure>.self
  ) { group in
    let body = body.takeSending()!
    group.addTask {
      do throws(Failure) {
        return .success(Disconnected(value: try await body()))
      } catch {
        return .error(error)
      }
    }
    group.addTask {
      do {
        try await clock.sleep(for: timeout, tolerance: tolerance)
        return .timedOut
      } catch {
        return .cancelled
      }
    }

    switch await group.next() {
    case .success(let result):
      // Work returned a result. Cancel the timer task and return
      group.cancelAll()
      return .success(result)
    case .error(let error):
      // Work threw. Cancel the timer task and rethrow
      group.cancelAll()
      return .failure(TimeoutError(underlying: error))
    case .timedOut:
      // Timed out, cancel the work task.
      group.cancelAll()

      switch await group.next() {
      case .success(let result):
        return .success(result)
      case .error(let error):
        return .failure(TimeoutError(underlying: error))
      case .timedOut, .cancelled, .none:
        // We already got a result from the sleeping task so we can't get another one or none.
        fatalError("Unexpected task result")
      }
    case .cancelled:
      switch await group.next() {
      case .success(let result):
        return .success(result)
      case .error(let error):
        return .failure(TimeoutError(underlying: error))
      case .timedOut, .cancelled, .none:
        // We already got a result from the sleeping task so we can't get another one or none.
        fatalError("Unexpected task result")
      }
    case .none:
      fatalError("Unexpected task result")
    }
  }
  return try result.get().take()
}
#endif

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// An error that indicates whether an operation failed due to deadline expiration or threw an error during
/// normal execution.
///
/// This error type distinguishes between two failure scenarios:
/// - The operation threw an error before the deadline expired.
/// - The operation was cancelled due to deadline expiration and then threw an error.
///
/// Use pattern matching to handle each case appropriately:
///
/// ```swift
/// let clock = ContinuousClock()
/// let deadline = clock.now.advanced(by: .seconds(5))
/// do {
///     let result = try await withDeadline(until: deadline, clock: clock) {
///         try await fetchDataFromServer()
///     }
///     print("Data received: \(result)")
/// } catch {
///     switch error.cause {
///     case .deadlineExceeded(let operationError):
///         print("Deadline exceeded and operation threw: \(operationError)")
///     case .operationFailed(let operationError):
///         print("Operation failed before deadline: \(operationError)")
///     }
/// }
/// ```
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
public struct DeadlineError<OperationError: Error, Clock: _Concurrency.Clock>: Error, CustomStringConvertible, CustomDebugStringConvertible {
  public enum Cause: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The operation was cancelled due to deadline expiration and subsequently threw an error.
    ///
    /// This case indicates the deadline instant passed, the operation was cancelled,
    /// and the operation threw an error during or after cancellation.
    case deadlineExceeded(OperationError)

    /// The operation threw an error before the deadline expired.
    ///
    /// This case indicates the operation failed on its own without the deadline
    /// being reached.
    case operationFailed(OperationError)

    public var description: String {
      switch self {
      case .deadlineExceeded(let error):
        return "\(error)"
      case .operationFailed(let error):
        return "\(error)"
      }
    }

    public var debugDescription: String {
      self.description
    }
  }
  /// The underlying cause of the deadline error, indicating whether the operation failed before the deadline
  /// or was cancelled due to deadline expiration.
  public var cause: Cause

  /// The clock used to measure time for the deadline.
  public var clock: Clock

  /// The deadline instant that was specified for the operation.
  public var instant: Clock.Instant

  public var description: String {
    "DeadlineError(cause: \(self.cause), clock: \(self.clock), instant: \(self.instant))"
  }

  public var debugDescription: String {
    return self.description
  }

  /// Creates a deadline error with the specified cause, clock, and deadline instant.
  ///
  /// Use this initializer to construct a ``DeadlineError`` that describes an operation's failure
  /// in relation to its deadline.
  ///
  /// - Parameters:
  ///   - cause: The underlying cause of the deadline error, indicating whether the operation
  ///     failed before the deadline or was cancelled due to deadline expiration.
  ///   - clock: The clock used to measure time for the deadline.
  ///   - instant: The deadline instant that was specified for the operation.
  public init(
    cause: Cause,
    clock: Clock,
    instant: Clock.Instant
  ) {
    self.cause = cause
    self.clock = clock
    self.instant = instant
  }
}

#if compiler(>=6.3)
/// Executes an asynchronous operation with a specified deadline.
///
/// Use this function to limit the execution time of an asynchronous operation to a specific instant.
/// If the operation completes before the deadline expires, this function returns the result. If the
/// deadline expires first, this function cancels the operation and throws a ``DeadlineError``.
///
/// The following example demonstrates using a deadline to limit a network request:
///
/// ```swift
/// let clock = ContinuousClock()
/// let deadline = clock.now.advanced(by: .seconds(5))
/// do {
///     let result = try await withDeadline(until: deadline, clock: clock) {
///         try await fetchDataFromServer()
///     }
///     print("Data received: \(result)")
/// } catch {
///     switch error.cause {
///     case .deadlineExceeded(let operationError):
///         print("Deadline exceeded and operation threw: \(operationError)")
///     case .operationFailed(let operationError):
///         print("Operation failed before deadline: \(operationError)")
///     }
/// }
/// ```
///
/// ## Behavior
///
/// The function exhibits the following behavior based on deadline and operation completion:
///
/// - If the operation completes successfully before deadline: Returns the operation's result.
/// - If the operation throws an error before deadline: Throws ``DeadlineError`` with cause
///  ``DeadlineError/Cause/operationFailed(_:)``.
/// - If deadline expires and operation completes successfully: Returns the operation's result.
/// - If deadline expires and operation throws an error: Throws ``DeadlineError`` with cause
///  ``DeadlineError/Cause/deadlineExceeded(_:).
///
/// ## Coordinating multiple operations
///
/// Use `withDeadline` when coordinating multiple operations to complete by the same instant:
///
/// ```swift
/// let clock = ContinuousClock()
/// let deadline = clock.now.advanced(by: .seconds(10))
///
/// async let result1 = withDeadline(until: deadline) {
///     try await fetchUserData()
/// }
/// async let result2 = withDeadline(until: deadline) {
///     try await fetchPreferences()
/// }
///
/// let (user, prefs) = try await (result1, result2)
/// ```
///
/// This ensures both operations share the same absolute deadline, avoiding duration drift that can occur
/// when timeouts are passed through multiple call layers.
///
/// - Important: This function cancels the operation when the deadline expires, but waits for the
/// operation to return. The function may run longer than the time until the deadline if the operation
/// doesn't respond to cancellation immediately.
///
/// - Parameters:
///   - deadline: The instant by which the operation must complete.
///   - tolerance: The tolerance used for the sleep.
///   - clock: The clock to use for measuring time. The default is `ContinuousClock`.
///   - body: The asynchronous operation to execute before the deadline.
///
/// - Returns: The result of the operation if it completes successfully before or after the deadline expires.
///
/// - Throws: A ``DeadlineError`` indicating whether the operation failed before deadline
/// (``DeadlineError/Cause/operationFailed(_:)``) or was cancelled due to deadline expiration
/// (``DeadlineError/Cause/deadlineExceeded(_:)``).
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) public func withDeadline<Return, Failure: Error, Clock: _Concurrency.Clock>(
  until deadline: Clock.Instant,
  tolerance: Clock.Instant.Duration? = nil,
  clock: Clock = .continuous,
  body: nonisolated(nonsending) () async throws(Failure) -> Return
) async throws(DeadlineError<Failure, Clock>) -> Return {
  nonisolated(unsafe) let body = body
  return try await _withDeadline(
    until: deadline,
    tolerance: tolerance,
    clock: clock
  ) { () async throws(Failure) -> Return in
    try await body()
  }
}
#elseif compiler(>=6.2)
// Duplicated due to the compiler not being able to infer the default
// generic clock type before 6.3
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) public func withDeadline<Return, Failure: Error, Clock: _Concurrency.Clock>(
  until deadline: Clock.Instant,
  tolerance: Clock.Instant.Duration? = nil,
  clock: Clock,
  body: nonisolated(nonsending) () async throws(Failure) -> Return
) async throws(DeadlineError<Failure, Clock>) -> Return {
  nonisolated(unsafe) let body = body
  return try await _withDeadline(
    until: deadline,
    tolerance: tolerance,
    clock: clock
  ) { () async throws(Failure) -> Return in
    try await body()
  }
}
#endif

#if compiler(>=6.2)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) func _withDeadline<Return, Failure: Error, Clock: _Concurrency.Clock>(
  until deadline: Clock.Instant,
  tolerance: Clock.Instant.Duration?,
  clock: Clock,
  body: @Sendable () async throws(Failure) -> Return
) async throws(DeadlineError<Failure, Clock>) -> Return {
  try await withoutActuallyEscaping(body) { (escapingBody) async throws(DeadlineError<Failure, Clock>) -> Return in
    var t = Optional(escapingBody)
    return try await __withDeadline(until: deadline, tolerance: tolerance, clock: clock, body: &t)
  }
}

private enum TaskResult<Return: Sendable, Failure: Error>: Sendable {
  case success(Return)
  case error(Failure)
  case timedOut
  case cancelled
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
nonisolated(nonsending) func __withDeadline<Return, Failure: Error, Clock: _Concurrency.Clock>(
  until deadline: Clock.Instant,
  tolerance: Clock.Instant.Duration?,
  clock: Clock,
  body: inout (@Sendable () async throws(Failure) -> Return)?
) async throws(DeadlineError<Failure, Clock>) -> Return {
  let result: Result<RefBox<Disconnected<Return>>, DeadlineError<Failure, Clock>> = await withTaskGroup(
    of: TaskResult<RefBox<Disconnected<Return>>, Failure>.self
  ) { group in
    let body = body.takeSending()!
    group.addTask {
      do throws(Failure) {
        return .success(RefBox(value: Disconnected(value: try await body())))
      } catch {
        return .error(error)
      }
    }
    group.addTask {
      do {
        try await clock.sleep(until: deadline, tolerance: tolerance)
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
      // Work threw before deadline. Cancel the timer task and throw operationFailed
      group.cancelAll()
      return .failure(DeadlineError(
          cause: .operationFailed(error),
          clock: clock,
          instant: deadline
      ))
    case .timedOut:
      // Deadline exceeded, cancel the work task.
      group.cancelAll()

      switch await group.next() {
      case .success(let result):
        return .success(result)
      case .error(let error):
        return .failure(DeadlineError(
          cause: .deadlineExceeded(error),
          clock: clock,
          instant: deadline
        ))
      case .timedOut, .cancelled, .none:
        // We already got a result from the sleeping task so we can't get another one or none.
        fatalError("Unexpected task result")
      }
    case .cancelled:
      switch await group.next() {
      case .success(let result):
        return .success(result)
      case .error(let error):
        return .failure(DeadlineError(
          cause: .deadlineExceeded(error),
          clock: clock,
          instant: deadline
        ))
      case .timedOut, .cancelled, .none:
        // We already got a result from the sleeping task so we can't get another one or none.
        fatalError("Unexpected task result")
      }
    case .none:
      fatalError("Unexpected task result")
    }
  }
  return try result.get().unbox().take()
}
#endif

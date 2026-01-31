# Deadline

* Proposal: [NNNN](NNNN-timeout.md)
* Authors: [Franz Busch](https://github.com/FranzBusch)
* Review Manager: TBD
* Status: **Implemented (https://github.com/apple/swift-async-algorithms/pull/396)**

## Introduction

This proposal introduces `withDeadline`, a function that executes asynchronous
operations with an absolute time limit. The function accepts a clock instant
representing the deadline by which the operation must complete. If the operation
completes before the deadline, the function returns the result; if the deadline
expires first, the operation is cancelled.

## Motivation

Asynchronous operations in Swift can run indefinitely, which creates several
problems in real-world applications:

1. Network operations may not complete when servers become unresponsive,
   consuming resources and degrading user experience.
2. Server-side applications need predictable request handling times to maintain
   service level agreements and prevent resource exhaustion.
3. Batch processing requires mechanisms to prevent individual tasks from
   blocking entire workflows.
4. Resource management becomes difficult when operations lack time bounds,
   leading to connection pool exhaustion and memory leaks.
5. Coordinating multiple operations to complete by a shared deadline requires
   passing absolute instants, not relative durations that drift through the call
   stack.

Currently, developers must implement timeout logic manually using task groups
and clock sleep operations, resulting in verbose, error-prone code that's
difficult to compose with surrounding async contexts. Each implementation must
carefully handle cancellation, error propagation, and race conditions between
the operation and timer.

## Proposed solution

This proposal introduces `withDeadline`, a function that executes an
asynchronous operation with an absolute time limit specified as a clock instant.
The solution provides a clean, composable API that handles cancellation and
error propagation automatically:

```swift
let clock = ContinuousClock()
let deadline = clock.now.advanced(by: .seconds(5))

do {
    let result = try await withDeadline(until: deadline, clock: clock) {
        try await fetchDataFromServer()
    }
    print("Data received: \(result)")
} catch {
    switch error.cause {
    case .deadlineExceeded(let operationError):
        print("Request exceeded deadline: \(operationError)")
    case .operationFailed(let operationError):
        print("Request failed: \(operationError)")
    }
}
```

The solution is safer than manual implementations because it handles all race
conditions between the operation and deadline timer, ensures proper cleanup
through structured concurrency, and provides clear semantics for cancellation
behavior.

## Detailed design

#### DeadlineError

```swift
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
public struct DeadlineError<OperationError: Error, Clock: _Concurrency.Clock>: Error, CustomStringConvertible, CustomDebugStringConvertible {
  /// The underlying cause of the deadline error.
  public enum Cause: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The operation was cancelled due to deadline expiration and subsequently threw an error.
    case deadlineExceeded(OperationError)

    /// The operation threw an error before the deadline expired.
    case operationFailed(OperationError)
  }

  /// The underlying cause of the deadline error, indicating whether the operation
  /// failed before the deadline or was cancelled due to deadline expiration.
  public var cause: Cause

  /// The clock used to measure time for the deadline.
  public var clock: Clock

  /// The deadline instant that was specified for the operation.
  public var instant: Clock.Instant

  /// Creates a deadline error with the specified cause, clock, and deadline instant.
  public init(cause: Cause, clock: Clock, instant: Clock.Instant)
}
```

`DeadlineError` is a struct that contains the cause of the failure, the clock
used for time measurement, and the deadline instant. The `Cause` enum
distinguishes between two failure scenarios:
- The operation threw an error before the deadline expired
  (`Cause.operationFailed`)
- The operation was cancelled due to deadline expiration and then threw an error
  (`Cause.deadlineExceeded`)

This allows callers to determine whether an error occurred due to deadline
expiration or due to the operation failing on its own, enabling different
recovery strategies. The additional `clock` and `instant` properties provide
context about the time measurement used and the specific deadline that was set.

#### withDeadline Function

```swift
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
nonisolated(nonsending) public func withDeadline<Return, Failure: Error, Clock: _Concurrency.Clock>(
  until deadline: Clock.Instant,
  tolerance: Clock.Instant.Duration? = nil,
  clock: Clock = .continuous,
  body: nonisolated(nonsending) () async throws(Failure) -> Return
) async throws(DeadlineError<Failure, Clock>) -> Return
```

The deadline-based API accepts a `Clock.Instant`, allowing multiple operations
to share the same absolute deadline:

```swift
let clock = ContinuousClock()
let deadline = clock.now.advanced(by: .seconds(10))

async let user = withDeadline(until: deadline, clock: clock) {
    try await fetchUser()
}
async let prefs = withDeadline(until: deadline, clock: clock) {
    try await fetchPreferences()
}

let (userData, prefsData) = try await (user, prefs)
```

#### Non-escaping nonisolated(nonsending) operation closure 

Many existing deadline/timeout implementations require a `@Sendable` and
`@escaping` closure which makes it hard to compose in isolated context and use
non-Sendable types. This design ensures that the closure is both non-escaping
and nonisolated(nonsending) for composability:

```swift
actor DataProcessor {
    var cache: [String: Data] = [:]

    func fetchWithDeadline(url: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))

        // The closure can access actor-isolated state because it's nonisolated(nonsending)
        let data = try await withDeadline(until: deadline, clock: clock) {
            if let cached = cache[url] {
                return cached
            }
            return try await URLSession.shared.data(from: URL(string: url)!)
        }
        cache[url] = data
    }
}
```

If the closure were `@Sendable`, it couldn't access actor-isolated state like
`cache`. The `nonisolated(nonsending)` annotation allows the closure to compose
with surrounding code regardless of isolation context, while maintaining safety
guarantees.

### Implementation Details

The implementation uses structured concurrency with task groups to race the
operation against a deadline timer:

1. Two tasks are created: one executes the operation, the other sleeps until the
   deadline.
2. The first task to complete determines the result.
3. When either task completes, `cancelAll()` cancels the other task.
4. If the deadline expires first, the operation is cancelled but the function
   waits for it to return.
5. The function handles both the operation's result and any errors thrown.

**Important behavioral note:** The function cancels the operation when the
deadline expires, but waits for the operation to return. This means
`withDeadline` may run longer than the time until the deadline if the operation
doesn't respond to cancellation immediately. This design ensures proper cleanup
and prevents resource leaks from abandoned tasks.

## Effect on API resilience

This is an additive API and no existing systems are changed, however it will
introduce a few new types that will need to be maintained as ABI interfaces.

## Alternatives considered

### Timeout-based API instead of Deadline-based API

An earlier design considered naming the primary API `withTimeout` and having it
accept a duration parameter instead of focusing on deadline-based
(instant-based) semantics:

```swift
public func withTimeout<Return, Failure: Error>(
  in duration: Duration,
  body: () async throws(Failure) -> Return
) async throws(TimeoutError<Failure>) -> Return
```

This approach was rejected because deadline-based APIs provide better
composability and semantics. Duration-based timeouts accumulate drift when
passed through multiple call layers, making it impossible to guarantee that
nested operations complete within a precise time window, whereas absolute
deadlines allow multiple operations to coordinate on the same completion
instant.

### @Sendable and @escaping Closure

An earlier design considered using `@Sendable` and `@escaping` for the closure
parameter. This approach was rejected because it severely limited composability. The
`@Sendable` requirement prevented accessing actor-isolated state, making it
difficult to use in isolated contexts. The final design uses
`nonisolated(nonsending)` to enable better composition while maintaining safety.

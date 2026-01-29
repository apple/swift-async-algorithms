# Timeout

* Proposal: [NNNN](NNNN-timeout.md)
* Authors: [Author 1](https://github.com/FranzBusch)
* Review Manager: TBD
* Status: **Implemented (https://github.com/apple/swift-async-algorithms/pull/396)**

## Introduction

This proposal introduces `withTimeout`, a function that executes an asynchronous
operation with a specified time limit. If the operation completes before the
timeout expires, the function returns the result; if the timeout expires first,
the operation is cancelled and a `TimeoutError` is thrown once the operation
completed.

## Motivation

Asynchronous operations in Swift can run indefinitely, which creates several
problems in real-world applications:

1. Network operations may not complete when servers become unresponsive, consuming
   resources and degrading user experience.
2. Server-side applications need predictable request handling times to maintain
   service level agreements and prevent resource exhaustion.
3. Batch processing requires mechanisms to prevent individual tasks from
   blocking entire workflows.
4. Resource management becomes difficult when operations lack time bounds,
   leading to connection pool exhaustion and memory leaks.

Currently, developers must implement timeout logic manually using task groups
and clock sleep operations, resulting in verbose, error-prone code that's
difficult to compose with surrounding async contexts. Each implementation must
carefully handle cancellation, error propagation, and race conditions between
the operation and timer.

## Proposed solution

This proposal introduces `withTimeout`, a function that executes an asynchronous
operation with a time limit. The solution provides a clean, composable API that
handles cancellation and error propagation automatically:

```swift
do {
    let result = try await withTimeout(in: .seconds(5)) {
        try await fetchDataFromServer()
    }
    print("Data received: \(result)")
} catch let error as TimeoutError<NetworkError> {
    print("Request timed out: \(error.underlying)")
}
```

The solution is safer than manual implementations because it handles all race
conditions between the operation and timeout timer, ensures proper cleanup
through structured concurrency, and provides clear semantics for cancellation
behavior.

## Detailed design

#### TimeoutError

```swift
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
```

`TimeoutError` wraps the original error type thrown by the timed-out operation,
preserving type information for error handling. This allows callers to access
the underlying error while clearly indicating that a timeout occurred.

#### withTimeout Function

```swift
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
nonisolated(nonsending) public func withTimeout<Return, Failure: Error, Clock: _Concurrency.Clock>(
  in timeout: Clock.Instant.Duration,
  tolerance: Clock.Instant.Duration? = nil,
  clock: Clock = .continuous,
  body: nonisolated(nonsending) () async throws(Failure) -> Return
) async throws(TimeoutError<Failure>) -> Return {
```

#### Non-escaping nonisolated(nonsending) operation closure 

Many existing `withTimeout` implementations require a `@Sendable` and
`@escaping` closure which makes it hard to compose in isolated context and use
non-Sendable types. This design ensures that the closure is both non-escaping
and nonisolated(nonsending) for composability:

```swift
actor DataProcessor {
    var cache: [String: Data] = [:]
    
    func fetchWithTimeout(url: String) async throws {
        // The closure can access actor-isolated state because it's nonisolated(nonsending)
        let data = try await withTimeout(in: .seconds(5)) {
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
operation against a timeout timer:

1. Two tasks are created: one executes the operation, the other sleeps for the
   timeout duration
2. The first task to complete determines the result
3. When either task completes, `cancelAll()` cancels the other task
4. If the timeout expires first, the operation is cancelled but the function
   waits for it to return
5. The function handles both the operation's result and any errors thrown

**Important behavioral note:** The function cancels the operation when the
timeout expires, but waits for the operation to return. This means `withTimeout`
may run longer than the specified timeout duration if the operation doesn't
respond to cancellation immediately. This design ensures proper cleanup and
prevents resource leaks from abandoned tasks.

## Effect on API resilience

This is an additive API and no existing systems are changed, however it will
introduce a few new types that will need to be maintained as ABI interfaces.
Since the intent of this is to provide a mechanism to store AsyncSequences to a
shared context the type must be exposed as ABI (for type sizing).

## Alternatives considered

### @Sendable and @escaping Closure

An earlier design considered using `@Sendable` and `@escaping` for the closure
parameter:

```swift
public func withTimeout<Return: Sendable, Failure: Error, Clock: _Concurrency.Clock>(
  in timeout: Clock.Duration,
  clock: Clock = ContinuousClock(),
  body: @Sendable @escaping () async throws(Failure) -> Return
) async throws(TimeoutError<Failure>) -> Return
```

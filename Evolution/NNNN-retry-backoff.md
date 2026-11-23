# Retry & Backoff

* Proposal: [NNNN](NNNN-retry-backoff.md)
* Authors: [Philipp Gabriel](https://github.com/ph1ps)
* Review Manager: TBD
* Status: **Implemented**

## Introduction

This proposal introduces a `retry` function and a suite of backoff strategies for Swift Async Algorithms, enabling robust retries of failed asynchronous operations with customizable delays and error-driven decisions.

Swift forums thread: [Discussion thread topic for that proposal](https://forums.swift.org/t/pitch-retry-backoff/82483)

## Motivation

Retry logic with backoff is a common requirement in asynchronous programming, especially for operations subject to transient failures such as network requests. Today, developers must reimplement retry loops manually, leading to fragmented and error-prone solutions across the ecosystem.  

Providing a standard `retry` function and reusable backoff strategies in Swift Async Algorithms ensures consistent, safe and well-tested patterns for handling transient failures.

## Proposed solution

This proposal includes a suite of backoff strategies that can be used to generate delays between retry attempts. `BackoffStrategy` is a protocol that defines an immutable configuration for generating delays, while `BackoffIterator` handles the stateful generation of successive delay durations. This design mirrors Swift's `Sequence`/`IteratorProtocol` pattern.

```swift
@available(AsyncAlgorithms 1.1, *)
public protocol BackoffStrategy<Duration> {
  associatedtype Iterator: BackoffIterator
  associatedtype Duration: DurationProtocol where Duration == Iterator.Duration
  func makeIterator() -> Iterator
}

@available(AsyncAlgorithms 1.1, *)
public protocol BackoffIterator {
  associatedtype Duration: DurationProtocol
  mutating func nextDuration() -> Duration
  mutating func nextDuration(using generator: inout some RandomNumberGenerator) -> Duration
}
```

`BackoffIterator` provides a default implementation of `nextDuration(using:)` that ignores the generator and forwards to `nextDuration()`. Iterators that use randomization (such as the jitter strategies) override this to use the provided generator instead of the system default.

The core strategies provide different patterns for calculating delays: constant intervals, linear growth, and exponential growth.

```swift
@available(AsyncAlgorithms 1.1, *)
public enum Backoff {
  public static func constant<Duration: DurationProtocol>(_ constant: Duration) -> some BackoffStrategy<Duration>
  public static func constant(_ constant: Duration) -> some BackoffStrategy<Duration>
  public static func linear(increment: Duration, initial: Duration) -> some BackoffStrategy<Duration>
  public static func exponential(factor: Int128, initial: Duration) -> some BackoffStrategy<Duration>
}
```

These strategies can be modified to enforce minimum or maximum delays, or to add jitter for preventing the thundering herd problem.

```swift
@available(AsyncAlgorithms 1.1, *)
extension BackoffStrategy {
  public func minimum(_ minimum: Duration) -> some BackoffStrategy<Duration>
  public func maximum(_ maximum: Duration) -> some BackoffStrategy<Duration>
}
@available(AsyncAlgorithms 1.1, *)
extension BackoffStrategy where Self: Sendable {
  public func minimum(_ minimum: Duration) -> some BackoffStrategy<Duration> & Sendable
  public func maximum(_ maximum: Duration) -> some BackoffStrategy<Duration> & Sendable
}
@available(AsyncAlgorithms 1.1, *)
extension BackoffStrategy where Duration == Swift.Duration {
  public func fullJitter() -> some BackoffStrategy<Duration>
  public func equalJitter() -> some BackoffStrategy<Duration>
}
@available(AsyncAlgorithms 1.1, *)
extension BackoffStrategy where Duration == Swift.Duration, Self: Sendable {
  public func fullJitter() -> some BackoffStrategy<Duration> & Sendable
  public func equalJitter() -> some BackoffStrategy<Duration> & Sendable
}
```

Linear, exponential, and jitter backoff require the use of `Swift.Duration` rather than any type conforming to `DurationProtocol` due to limitations of `DurationProtocol` to do more complex mathematical operations, such as adding or multiplying with reporting overflows or generating random values. Constant, minimum and maximum are able to use `DurationProtocol`.

This proposal also introduces a retry function that executes an asynchronous operation up to a specified number of attempts, with customizable delays and error-based retry decisions between attempts.

```swift
@available(AsyncAlgorithms 1.1, *)
nonisolated(nonsending) public func retry<Result, ErrorType, DurationType>(
  maxAttempts: Int,
  tolerance: DurationType? = nil,
  clock: any Clock<DurationType>,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> RetryAction<DurationType> = { _ in .backoff(.zero) }
) async throws -> Result where DurationType: DurationProtocol, ErrorType: Error
```

```swift
@available(AsyncAlgorithms 1.1, *)
public struct RetryAction<Duration: DurationProtocol> {
  public static var stop: Self
  public static func backoff(_ duration: Duration) -> Self
}
```

For convenience, there are also overloads that accept a `BackoffStrategy` directly. These overloads automatically compute the next backoff duration from the strategy on each retry, and replace the `strategy` closure with a simpler `strategy` closure that returns `Bool` instead of `RetryAction`:

```swift
@available(AsyncAlgorithms 1.1, *)
nonisolated(nonsending) public func retry<Result, ErrorType, DurationType, Strategy>(
  maxAttempts: Int,
  backoff: Strategy,
  tolerance: DurationType? = nil,
  clock: any Clock<DurationType>,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> Bool = { _ in true }
) async throws -> Result where DurationType: DurationProtocol, ErrorType: Error, Strategy: BackoffStrategy<DurationType>
```

For each retry overload, there is also a convenience variant that omits the `clock` parameter and uses `ContinuousClock` by default. This provides ergonomic defaults for the common case:

```swift
// Without explicit clock (uses ContinuousClock)
try await retry(maxAttempts: 5, backoff: backoff) {
  try await operation()
}

// With explicit clock
try await retry(maxAttempts: 5, backoff: backoff, clock: myClock) {
  try await operation()
}
```

There are also overloads that accept an `inout RandomNumberGenerator` and forward it to `nextDuration(using:)` on each retry. This allows callers to inject a seeded generator for deterministic testing of jitter strategies:

```swift
@available(AsyncAlgorithms 1.1, *)
nonisolated(nonsending) public func retry<Result, ErrorType, DurationType, Strategy>(
  maxAttempts: Int,
  backoff: Strategy,
  using generator: inout some RandomNumberGenerator,
  tolerance: DurationType? = nil,
  clock: any Clock<DurationType>,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> Bool = { _ in true }
) async throws -> Result where DurationType: DurationProtocol, ErrorType: Error, Strategy: BackoffStrategy<DurationType>
```

## Detailed design

### Retry

The retry algorithm follows this sequence:
1. Execute the operation
2. If successful, return the result
3. If failed and this was not the final attempt:
   - Call the `strategy` closure with the error
     - If the strategy returns `.stop`, rethrow the error immediately
     - If the strategy returns `.backoff`, suspend for the given duration
       - Return to step 1
4. If failed on the final attempt, rethrow the error without consulting the strategy

Given this sequence, there are four termination conditions (when retrying will be stopped):
- The operation completes without throwing an error
- The operation has been attempted `maxAttempts` times
- The strategy closure returns `.stop`
- The clock throws

#### Preconditions

- `maxAttempts` must be greater than 0. Passing 0 or a negative value triggers a precondition failure.

#### Cancellation

`retry` does not introduce special cancellation handling. If your code cooperatively cancels by throwing, ensure your strategy returns `.stop` for that error. Otherwise, retries continue unless the clock throws on cancellation.

### Backoff

#### Modifier composition

Backoff modifiers are applied in the order they are chained. This order affects the final computed duration:

```swift
// Jitter applied to the capped value (0 to 5 seconds)
let a = Backoff.exponential(factor: 2, initial: .seconds(1))
  .maximum(.seconds(5))
  .fullJitter()

// Jitter applied first, then capped (never exceeds 5 seconds)
let b = Backoff.exponential(factor: 2, initial: .seconds(1))
  .fullJitter()
  .maximum(.seconds(5))
```

In the first example, when the exponential reaches 8 seconds, it is capped to 5 seconds, then jitter produces a value between 0 and 5 seconds. In the second example, jitter is applied to the full 8 seconds first (producing 0 to 8 seconds), then the result is capped at 5 seconds.

#### Custom backoff

Adopters may create their own backoff logic. The base `retry` function accepts a `strategy` closure that returns `RetryAction`, allowing complete control over backoff durations without conforming to any protocol. To use the `retry` overloads that accept a `backoff` parameter, or to use the provided modifiers (`minimum`, `maximum`, `fullJitter`, `equalJitter`), a custom strategy must conform to `BackoffStrategy`.

#### Standard backoff

The strategies compute durations according to these formulas:

- **Constant**: $f(n) = constant$
- **Linear**: $f(n) = initial + increment * n$
- **Exponential**: $f(n) = initial * factor ^ n$
- **Minimum**: $f(n) = max(minimum, g(n))$ where $g(n)$ is the base strategy
- **Maximum**: $f(n) = min(maximum, g(n))$ where $g(n)$ is the base strategy
- **Full Jitter**: $f(n) = random(0, g(n))$ where $g(n)$ is the base strategy
- **Equal Jitter**: $f(n) = random(g(n)/2, g(n))$ where $g(n)$ is the base strategy

##### Overflow Handling

Linear and exponential backoff strategies perform overflow-checked arithmetic. If the computed duration would overflow, the strategy returns `Duration(attoseconds: .max)` for all subsequent calls. This ensures the program does not crash due to overflow.

Note that wrapper strategies like `.maximum()` continue calling their base iterator even after the maximum is reached, so the underlying iterator can still reach overflow state. However, since the wrapper clamps the result, the effective duration remains bounded.

##### Sendability

The core backoff strategies returned by `Backoff.constant`, `Backoff.linear`, and `Backoff.exponential` are unconditionally `Sendable`. The modifier methods (`minimum`, `maximum`, `fullJitter`, `equalJitter`) use overloads to preserve `Sendable` conformance: when called on a `Sendable` strategy, they return `some BackoffStrategy<Duration> & Sendable`; otherwise they return `some BackoffStrategy<Duration>`. This allows strategies to be stored and shared across isolation domains. Iterators are stateful and should not be shared; create a fresh iterator via `makeIterator()` in each context.

### Case studies

The most common use cases encountered for recovering from transient failures are either:
- a system requiring its user to come up with a reasonable duration to let the system cool off
- a system providing its own duration which the user is supposed to honor to let the system cool off

Both of these use cases can be implemented using the proposed algorithm, respectively:

```swift
let backoff = Backoff
  .exponential(factor: 2, initial: .milliseconds(100))
  .maximum(.seconds(10))
  .fullJitter()

let response = try await retry(maxAttempts: 5, backoff: backoff) {
  try await URLSession.shared.data(from: url)
}
```

```swift
let response = try await retry(maxAttempts: 5) {
  let (data, response) = try await URLSession.shared.data(from: url)
  if
    let response = response as? HTTPURLResponse,
    response.statusCode == 429,
    let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
    let seconds = Double(retryAfter)
  {
    throw TooManyRequestsError(retryAfter: seconds)
  }
  return (data, response)
} strategy: { error in
  if let error = error as? TooManyRequestsError {
    return .backoff(.seconds(error.retryAfter))
  } else {
    return .stop
  }
}
```
(For demonstration purposes only, a network server is used as the remote system.)

## Effect on API resilience

This proposal introduces a purely additive API with no impact on existing functionality or API resilience.

## Alternatives considered

### Passing attempt number to `BackoffIterator`

Another option considered was to pass the current attempt number into the `BackoffIterator`.

Although this initially seems useful, it leads to an awkward semi-stateful design. Consider a Fibonacci backoff: if the attempt number is passed externally, the iterator would need to recompute the entire sequence up to that attempt on every call, or else maintain internal state anyway. True iterators track their own progression (e.g. storing the last duration), making each `nextDuration()` call O(1) rather than O(n). Passing the attempt number externally undermines this efficiency and creates confusion about where state belongs.

If adopters require access to the attempt number, they are free to implement this themselves, since the strategy closure is invoked each time a failure occurs, making it straightforward to maintain an external attempt counter.

### Retry on `AsyncSequence`

An alternative considered was adding retry functionality directly to `AsyncSequence` types, similar to how Combine provides retry on `Publisher`. However, after careful consideration, this was not included in the current proposal due to the lack of compelling real-world use cases.

If specific use cases emerge in the future that demonstrate clear value for async sequence retry functionality, this could be considered in a separate proposal or amended to this proposal.

### Random Number Generator Injection

Jitter strategies require a source of randomness. The options considered were:
1. Store the `RandomNumberGenerator` in the strategy or iterator
2. Pass the generator at each duration computation

Storing `inout` values is not possible in Swift. The alternative would be to store a copy of the `RandomNumberGenerator`, but there is no precedent for copying random number generators in the standard library. Therefore, the design passes `inout some RandomNumberGenerator` to `nextDuration(using:)`.

## Acknowledgments

Thanks to [Philippe Hausler](https://github.com/phausler), [Franz Busch](https://github.com/FranzBusch) and [Honza Dvorsky](https://github.com/czechboy0) for their thoughtful feedback and suggestions that helped refine the API design and improve its clarity and usability.

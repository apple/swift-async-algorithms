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

This proposal introduces a retry function that executes an asynchronous operation up to a specified number of attempts, with customizable delays and error-based retry decisions between attempts.

```swift
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
nonisolated(nonsending) public func retry<Result, ErrorType, ClockType>(
  maxAttempts: Int,
  tolerance: ClockType.Instant.Duration? = nil,
  clock: ClockType = ContinuousClock(),
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> RetryAction<ClockType.Instant.Duration> = { _ in .backoff(.zero) }
) async throws -> Result where ClockType: Clock, ErrorType: Error
```

```swift
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public enum RetryAction<Duration: DurationProtocol> {
  case backoff(Duration)
  case stop
}
```

Additionally, this proposal includes a suite of backoff strategies that can be used to generate delays between retry attempts. The core strategies provide different patterns for calculating delays: constant intervals, linear growth, exponential growth, and decorrelated jitter.

```swift
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public enum Backoff {
  public static func constant<Duration: DurationProtocol>(_ constant: Duration) -> some BackoffStrategy<Duration>
  public static func constant(_ constant: Duration) -> some BackoffStrategy<Duration>
  public static func linear<Duration: DurationProtocol>(increment: Duration, initial: Duration) -> some BackoffStrategy<Duration>
  public static func linear(increment: Duration, initial: Duration) -> some BackoffStrategy<Duration>
  public static func exponential<Duration: DurationProtocol>(factor: Int, initial: Duration) -> some BackoffStrategy<Duration>
  public static func exponential(factor: Int, initial: Duration) -> some BackoffStrategy<Duration>
}
@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension Backoff {
  public static func decorrelatedJitter<RNG: RandomNumberGenerator>(factor: Int, base: Duration, using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration>
}
```

These strategies can be modified to enforce minimum or maximum delays, or to add jitter for preventing the thundering herd problem.

```swift
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
extension BackoffStrategy {
  public func minimum(_ minimum: Duration) -> some BackoffStrategy<Duration>
  public func maximum(_ maximum: Duration) -> some BackoffStrategy<Duration>
}
@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension BackoffStrategy where Duration == Swift.Duration {
  public func fullJitter<RNG: RandomNumberGenerator>(using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration>
  public func equalJitter<RNG: RandomNumberGenerator>(using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration>
}
```

Constant, linear, and exponential backoff provide overloads for both `Duration` and `DurationProtocol`. This matches the `retry` overloads where the default clock is `ContinuousClock` whose duration type is `Duration`.

Jitter variants currently require `Duration` rather than a generic `DurationProtocol`, because only `Duration` exposes a numeric representation suitable for randomization (see [SE-0457](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0457-duration-attosecond-represenation.md)).

Each of those strategies conforms to the `BackoffStrategy` protocol:

```swift
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public protocol BackoffStrategy<Duration> {
  associatedtype Duration: DurationProtocol
  mutating func nextDuration() -> Duration
}
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

#### Cancellation

`retry` does not introduce special cancellation handling. If your code cooperatively cancels by throwing, ensure your strategy returns `.stop` for that error. Otherwise, retries continue unless the clock throws on cancellation (which, at the time of writing, both `ContinuousClock` and `SuspendingClock` do).

### Backoff

All proposed strategies conform to `BackoffStrategy` which allows for builder-like syntax like this:
```swift
var backoff = Backoff
  .exponential(factor: 2, initial: .milliseconds(100))
  .maximum(.seconds(5))
  .fullJitter()
```

#### Custom backoff

Adopters may choose to create their own strategies. There is no requirement to conform to `BackoffStrategy`, since retry and backoff are decoupled; however, to use the provided modifiers (`minimum`, `maximum`, `jitter`), a strategy must conform.

Each call to `nextDuration()` returns the delay for the next retry attempt. Strategies are naturally stateful. For instance, they may track the number of invocations or the previously returned duration to calculate the next delay.

#### Standard backoff

As previously mentioned this proposal introduces several common backoff strategies which include: 

- **Constant**: $f(n) = constant$
- **Linear**: $f(n) = initial + increment * n$
- **Exponential**: $f(n) = initial * factor ^ n$
- **Decorrelated Jitter**: $f(n) = random(base, f(n - 1) * factor)$ where $f(0) = base$
- **Minimum**: $f(n) = max(minimum, g(n))$ where $g(n)$ is the base strategy
- **Maximum**: $f(n) = min(maximum, g(n))$ where $g(n)$ is the base strategy
- **Full Jitter**: $f(n) = random(0, g(n))$ where $g(n)$ is the base strategy
- **Equal Jitter**: $f(n) = random(g(n) / 2, g(n))$ where $g(n)$ is the base strategy

##### Sendability

The proposed backoff strategies are not marked `Sendable`.  
They are not meant to be shared across isolation domains, because their state evolves with each call to `nextDuration()`.  
Re-creating the strategies when they are used in different domains is usually the correct approach.

### Case studies

The most common use cases encountered for recovering from transient failures are either:
- a system requiring its user to come up with a reasonable duration to let the system cool off
- a system providing its own duration which the user is supposed to honor to let the system cool off

Both of these use cases can be implemented using the proposed algorithm, respectively:

```swift
let rng = SystemRandomNumberGenerator() // or a seeded RNG for unit tests
var backoff = Backoff
  .exponential(factor: 2, initial: .milliseconds(100))
  .maximum(.seconds(10))
  .fullJitter(using: rng)

let response = try await retry(maxAttempts: 5) {
  try await URLSession.shared.data(from: url)
} strategy: { error in
  return .backoff(backoff.nextDuration())
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

## Future directions

The jitter variants introduced by this proposal support custom `RandomNumberGenerator` by **copying** it in order to perform the necessary mutations. 
This is not optimal and does not match the standard library's signatures of e.g. `shuffle()` or `randomElement()` which take an **`inout`** random number generator.  
Due to the composability of backoff algorithms proposed here, this is not possible to adopt in current Swift.  
If Swift gains the capability to "store" `inout` variables, the jitter variants should adopt this by adding new `inout` overloads and deprecating the copying overloads.

## Alternatives considered

### Passing attempt number to `BackoffStrategy `

Another option considered was to pass the current attempt number into the `BackoffStrategy`.

Although this initially seems useful, it conflicts with the idea of strategies being stateful. A strategy is supposed to track its own progression (e.g. by counting invocations or storing the last duration). If the attempt number were provided externally, strategies would become "semi-stateful": mutating because of internal components such as a `RandomNumberGenerator`, but at the same time relying on an external counter instead of their own stored history. This dual model is harder to reason about and less consistent, so it was deliberately avoided.  

If adopters require access to the attempt number, they are free to implement this themselves, since the strategy is invoked each time a failure occurs, making it straightforward to maintain an external attempt counter.

### Retry on `AsyncSequence`

An alternative considered was adding retry functionality directly to `AsyncSequence` types, similar to how Combine provides retry on `Publisher`. However, after careful consideration, this was not included in the current proposal due to the lack of compelling real-world use cases.

If specific use cases emerge in the future that demonstrate clear value for async sequence retry functionality, this could be considered in a separate proposal or amended to this proposal.

## Acknowledgments

Thanks to [Philippe Hausler](https://github.com/phausler), [Franz Busch](https://github.com/FranzBusch) and [Honza Dvorsky](https://github.com/czechboy0) for their thoughtful feedback and suggestions that helped refine the API design and improve its clarity and usability.

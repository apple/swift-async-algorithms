# Throttle

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncThrottleSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestThrottle.swift)
]

## Introduction

When events can potentially happen faster than the desired consumption rate, there are multiple ways to handle the situation. One approach is to emit values after a given period has elapsed. These emitted values can be reduced from the values encountered during the waiting period. This algorithm is commonly referred to as throttling. 

## Proposed Solution

The throttle algorithm produces elements such that at least a specific interval has elapsed between them. It transacts by measuring against a specific clock. If values are produced by the base `AsyncSequence` the throttle does not resume its next iterator until the period has elapsed or unless a terminal event is encountered.

The interface for this algorithm is available on all `AsyncSequence` types. Unlike other algorithms like `debounce`, the throttle algorithm does not need to create additional tasks or require any sort of tolerance because the interval is just measured. A shorthand implementation will be offered in conjunction where the clock is the `ContinuousClock`, which allows for easy construction with `Duration` values. An additional shorthand is offered to reduce the values such that it provides a "latest" or "earliest" value, representing the leading or trailing edge of a throttled region of production of events.

```swift
extension AsyncSequence {
  public func throttle<C: Clock, Reduced>(
    for interval: C.Instant.Duration, 
    clock: C, 
    reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced
  ) -> AsyncThrottleSequence<Self, C, Reduced>
  
  public func throttle<Reduced>(
    for interval: Duration, 
    reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced
  ) -> AsyncThrottleSequence<Self, ContinuousClock, Reduced>
  
  public func throttle<C: Clock>(
    for interval: C.Instant.Duration, 
    clock: C, 
    latest: Bool = true
  ) -> AsyncThrottleSequence<Self, C, Element>
  
  public func throttle(
    for interval: Duration, 
    latest: Bool = true
  ) -> AsyncThrottleSequence<Self, ContinuousClock, Element>
}
```

This all boils down to a terse description of how to transform the asynchronous sequence over time. 

```swift
fastEvents.throttle(for: .seconds(1))
```

In this case, the throttle transforms a potentially fast asynchronous sequence of events into one that waits for a window of 1 second to elapse before emitting a value.

## Detailed Design

The type that implements the algorithm for throttle emits the same element type as the base that it applies to. It also throws when the base type throws (and likewise does not throw when the base type does not throw).

```swift
public struct AsyncThrottleSequence<Base: AsyncSequence, C: Clock, Reduced> {
}

extension AsyncThrottleSequence: AsyncSequence {
  public typealias Element = Reduced
  
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Reduced?
  }
  
  public func makeAsyncIterator() -> Iterator
}

extension AsyncThrottleSequence: Sendable 
  where Base: Sendable, Element: Sendable { }
extension AsyncThrottleSequence.Iterator: Sendable 
  where Base.AsyncIterator: Sendable { }
```

The `AsyncThrottleSequence` and its `Iterator` are conditionally `Sendable` if the base types comprising it are `Sendable`.

The time in which events are measured are from the previous emission if present. If a duration has elapsed between the last emission and the point in time the throttle is measured then that duration is counted as elapsed. The first element is considered not throttled because no interval can be constructed from the start to the first element.

## Alternatives Considered

It was considered to only provide the "latest" style APIs, however the reduction version grants more flexibility and can act as a funnel to the implementations of `latest`.

## Credits/Inspiration

http://reactivex.io/documentation/operators/sample.html

https://developer.apple.com/documentation/combine/publishers/throttle/

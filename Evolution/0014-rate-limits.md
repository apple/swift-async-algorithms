# Rate Limiting

* Proposal: [SAA-0014](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0014-rate-limits.md)
* Authors: [Philippe Hausler](https://github.com/phausler)
* Status: **Accepted**
* Implementation: 
[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncDebounceSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestDebounce.swift)
]
[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncThrottleSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestThrottle.swift)
]

* Decision Notes: 
* Bugs: 

## Introduction

When events can potentially happen faster than the desired consumption rate, there are multiple ways to handle the situation. One approach is to only emit values after a given period of time of inactivity, or "quiescence", has elapsed. This algorithm is commonly referred to as debouncing. A very close relative is an approach to emit values after a given period has elapsed. These emitted values can be reduced from the values encountered during the waiting period. This algorithm is commonly referred to as throttling. 

## Proposed Solution

The debounce algorithm produces elements after a particular duration has passed between events. It transacts within a given tolerance applied to a clock. If values are produced by the base `AsyncSequence` during this quiet period, the debounce does not resume its next iterator until the period has elapsed with no values are produced or unless a terminal event is encountered.

The interface for this algorithm is available on all `AsyncSequence` types where the base type, iterator, and element are `Sendable`, since this algorithm will inherently create tasks to manage their timing of events. A shorthand implementation will be offered where the clock is the `ContinuousClock`, which allows for easy construction with `Duration` values.

```swift
extension AsyncSequence {
  public func debounce<C: Clock>(
    for interval: C.Instant.Duration, 
    tolerance: C.Instant.Duration? = nil, 
    clock: C
  ) -> AsyncDebounceSequence<Self, C>
  
  public func debounce(
    for interval: Duration, 
    tolerance: Duration? = nil
  ) -> AsyncDebounceSequence<Self, ContinuousClock>
}
```

This all boils down to a terse description of how to transform the asynchronous sequence over time. 

```swift
fastEvents.debounce(for: .seconds(1))
```

In this case it transforms a potentially fast asynchronous sequence of events into one that waits for a window of 1 second with no events to elapse before emitting a value.

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

### Debounce

The type that implements the algorithm for debounce emits the same element type as the base that it applies to. It also throws when the base type throws (and likewise does not throw when the base type does not throw).

```swift
public struct AsyncDebounceSequence<Base: AsyncSequence, C: Clock>: Sendable
  where Base.Element: Sendable, Base: Sendable {
}

extension AsyncDebounceSequence: AsyncSequence {
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Base.Element? 
  }
  
  public func makeAsyncIterator() -> Iterator
}
```

Since the stored types comprising `AsyncDebounceSequence` must be `Sendable`; `AsyncDebounceSequence` is unconditionally always `Sendable`. It is worth noting that the iterators are not required to be Sendable.

### Throttle

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
```

The `AsyncThrottleSequence` is conditionally `Sendable` if the base types comprising it are `Sendable`.

The time in which events are measured are from the previous emission if present. If a duration has elapsed between the last emission and the point in time the throttle is measured then that duration is counted as elapsed. The first element is considered not throttled because no interval can be constructed from the start to the first element.

## Alternatives Considered

An alternative form of `debounce` could exist similar to the reductions of `throttle`, where a closure would be invoked for each value being set as the latest, and reducing a new value to produce for the debounce.

It was considered to only provide the "latest" style APIs, however the reduction version grants more flexibility and can act as a funnel to the implementations of `latest`.

## Credits/Inspiration

The naming for debounce comes as a term of art; originally this term was inspired by electronic circuitry. When a physical switch closes a circuit it can easily have a "bouncing" behavior (also called chatter) that is caused by electrical contact resistance and the physical bounce of springs associated with switches. That phenomenon is often addressed with additional circuits to de-bounce (removing the bouncing) by ensuring a certain quiescence occurs.

http://reactivex.io/documentation/operators/debounce.html

https://developer.apple.com/documentation/combine/publishers/debounce/

http://reactivex.io/documentation/operators/sample.html

https://developer.apple.com/documentation/combine/publishers/throttle/


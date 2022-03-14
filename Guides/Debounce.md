# Debounce

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncDebounceSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestDebounce.swift)
]

## Introduction

When events can potentially happen faster than the desired consumption rate there are multiple ways of handling that. One way of approaching that problem is to only emit values after a given period of time of quiessence has elapsed. This algorithm is commonly referred to as debouncing. 

## Proposed Solution

The debounce algorithm produces elements after a particular duration has passed between events. It transacts within a given tolerance applied to a clock. If values are produced by the base `AsyncSequence` the debounce does not resume it's next iterator until the period has elapsed with no values are produced or unless a terminal event is encountered.

The interface for this algorithm is available on all `AsyncSequence` types where the base type, iterator, and element are `Sendable`; since this will inherently create tasks to manage those timing of events. A shorthand implementation will be offered in conjunction where the clock is the `ContinuousClock`; which allows for easy construction with `Duration` values.

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

## Detailed Design

The type that implements the algorithm for debounce emits the same element type as the base that it applies to. It also throws when the base type throws (and likewise does not throw when the base type does not throw).

```swift
public struct AsyncDebounceSequence<Base: AsyncSequence, C: Clock>: Sendable
  where Base.AsyncIterator: Sendable, Base.Element: Sendable, Base: Sendable {
}

extension AsyncDebounceSequence: AsyncSequence {
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public mutating func next() async rethrows -> Base.Element? 
  }
  
  public func makeAsyncIterator() -> Iterator
}
```

Since the stored types comprising `AsyncDebounceSequence` must be `Sendable`; `AsyncDebounceSequence` is unconditionally always `Sendable`.

## Credits/Inspiration

The naming for debounce comes as a term of art; originally this term was inspired by electronic circutry. When a physical switch closes a circuit it can easily have a "bouncing" behavior (also called chatter) that is caused by electrical contact resistance and the physical bounce of springs associated with switches. That phenomenon is often addressed with additional circuits to de-bounce (removing the bouncing) by ensuring a certain quiessence occurs.

http://reactivex.io/documentation/operators/debounce.html

https://developer.apple.com/documentation/combine/publishers/debounce/

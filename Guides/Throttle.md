# Throttle

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncThrottleSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestThrottle.swift)
]

## Introduction

## Proposed Solution

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

## Detailed Design

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

## Alternatives Considered

## Credits/Inspiration

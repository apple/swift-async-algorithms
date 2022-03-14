# Timer

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncTimerSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestTimer.swift)
]

## Introduction

## Proposed Solution

```swift
public struct AsyncTimerSequence<C: Clock>: AsyncSequence {
  public typealias Element = C.Instant
  
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async -> C.Instant?
  }
  
  public init(
    interval: C.Instant.Duration, 
    tolerance: C.Instant.Duration? = nil, 
    clock: C
  )
  
  public func makeAsyncIterator() -> Iterator
}
```

## Detailed Design

## Alternatives Considered

## Credits/Inspiration

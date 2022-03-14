# Debounce

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncDebounceSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestDebounce.swift)
]

## Introduction

## Proposed Solution

```swift
extension AsyncSequence {
  public func debounce<C: Clock>(
    for interval: C.Instant.Duration, 
    tolerance: C.Instant.Duration? = nil, 
    clock: C
  ) -> AsyncDebounceSequence<Self, C>
}
```

## Detailed Design

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

## Alternatives Considered

## Credits/Inspiration

# Compacted

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncCompactedSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestCompacted.swift)
]

## Introduction

## Proposed Solution

```swift
extension AsyncSequence {
  public func compacted<Unwrapped>() -> AsyncCompactedSequence<Self, Unwrapped>
    where Element == Unwrapped?
}
```

## Detailed Design

```swift
public struct AsyncCompactedSequence<Base: AsyncSequence, Element>: AsyncSequence
  where Base.Element == Element? {

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator())
  }
}

extension AsyncCompactedSequence: Sendable 
  where 
    Base: Sendable, Base.Element: Sendable, 
    Base.AsyncIterator: Sendable { }
  
extension AsyncCompactedSequence.Iterator: Sendable 
  where 
    Base: Sendable, Base.Element: Sendable, 
    Base.AsyncIterator: Sendable { }
```

## Alternatives Considered

## Credits/Inspiration

This transformation function is a direct analog to the synchronous version [defined in the Swift Algorithms package](https://github.com/apple/swift-algorithms/blob/main/Guides/Compacted.md)

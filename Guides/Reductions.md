# Reductions

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncExclusiveReductionsSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestReductions.swift)
]

## Introduction

## Proposed Solution

```swift
extension AsyncSequence {
  public func reductions<Result>(
    _ initial: Result, 
    _ transform: @Sendable @escaping (Result, Element) async -> Result
  ) -> AsyncExclusiveReductionsSequence<Self, Result>
  
  public func reductions<Result>(
    into initial: Result, 
    _ transform: @Sendable @escaping (inout Result, Element) async -> Void
  ) -> AsyncExclusiveReductionsSequence<Self, Result>
}

extension AsyncSequence {
  public func reductions<Result>(
    _ initial: Result, 
    _ transform: @Sendable @escaping (Result, Element) async throws -> Result
  ) -> AsyncThrowingExclusiveReductionsSequence<Self, Result>
  
  public func reductions<Result>(
    into initial: Result, 
    _ transform: @Sendable @escaping (inout Result, Element) async throws -> Void
  ) -> AsyncThrowingExclusiveReductionsSequence<Self, Result>
}
```

## Detailed Design

```swift
public struct AsyncExclusiveReductionsSequence<Base: AsyncSequence, Element> {
}

extension AsyncExclusiveReductionsSequence: AsyncSequence {
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }
  
  public func makeAsyncIterator() -> Iterator
}

extension AsyncExclusiveReductionsSequence: Sendable 
  where Base: Sendable, Element: Sendable { }
  
extension AsyncExclusiveReductionsSequence.Iterator: Sendable 
  where Base.AsyncIterator: Sendable, Element: Sendable { }
```

```swift
public struct AsyncThrowingExclusiveReductionsSequence<Base: AsyncSequence, Element> {
}

extension AsyncThrowingExclusiveReductionsSequence: AsyncSequence {
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async throws -> Element?
  }
  
  public func makeAsyncIterator() -> Iterator
}

extension AsyncThrowingExclusiveReductionsSequence: Sendable 
  where Base: Sendable, Element: Sendable { }
  
extension AsyncThrowingExclusiveReductionsSequence.Iterator: Sendable 
  where Base.AsyncIterator: Sendable, Element: Sendable { }
```

## Alternatives Considered

## Credits/Inspiration

This transformation function is a direct analog to the synchronous version [defined in the Swift Algorithms package](https://github.com/apple/swift-algorithms/blob/main/Guides/Reductions.md)

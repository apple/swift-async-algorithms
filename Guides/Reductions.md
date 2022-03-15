# Reductions

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncExclusiveReductionsSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestReductions.swift)
]

## Introduction

The family of algorithms for reduce are useful to convert a sequence or asynchronous sequence into a single value, but that can elide important intermediate information. This algorithm is often called scan but that does not infer it's heritage to the family of reducing. There are two strategies that are usable for creating continuous reductions; either exclusive reductions or, inclusive reductions. Exclusive reductions take a value and incorperate values into that initial value; a common example is reductions by appending to an array. Inclusive reductions transact just upon the values provided; a common example is adding numbers. 

## Proposed Solution

Exclusive reductions come in two variants; either transforming by application, or transformation via mutation. This replicates the same interface as `reduce(_:_:)` and `reduce(into:_:)`. Unlike the `reduce` algorithms, the `reductions` algorithm also comes in two flavors; throwing or non throwing transformations.

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

Inclusive reductions do not have an initial value and so therefore do not need an additional variations beyond the throwing and non throwing flavors.

```swift
extension AsyncSequence {
  public func reductions(
    _ transform: @Sendable @escaping (Element, Element) async -> Element
  ) -> AsyncInclusiveReductionsSequence<Self>
  
  public func reductions(
    _ transform: @Sendable @escaping (Element, Element) async throws -> Element
  ) -> AsyncThrowingInclusiveReductionsSequence<Self>
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

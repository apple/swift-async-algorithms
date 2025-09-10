# Reductions
* Proposal: [SAA-0015](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0015-reductions.md)
* Author(s): [Philippe Hausler](https://github.com/phausler)
* Status: **Accepted**
* Implementation: [
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncExclusiveReductionsSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestReductions.swift)
]
* Decision Notes:
* Bugs:

## Introduction

The family of algorithms for reduce are useful for converting a sequence or asynchronous sequence into a single value, but that can elide important intermediate information. The _reductions_ algorithm is often called "scan", but this name does not convey its heritage to the family of reducing.

There are two strategies that are usable for creating continuous reductions: exclusive reductions and inclusive reductions:

 * Exclusive reductions take a value and incorporate values into that initial value. A common example is reductions by appending to an array.
 * Inclusive reductions transact only on the values provided. A common example is adding numbers. 

 There are also common specializations of this algorithm that are worth offering as a shorthand. Particularly removing duplications that is a common task of reducing a sequence. When processing values over time it is definitely possible that the same value may occur in a row. When the distinctness of the presence value is not needed it is useful to consider the values over time that are differing from the last. Particularly this can be expressed as removing duplicate values either in the case as they are directly `Equatable` or by a predicate.

## Proposed Solution

Exclusive reductions come in two variants: transforming by application, or transformation via mutation. This replicates the same interface as `reduce(_:_:)` and `reduce(into:_:)`. Unlike the `reduce` algorithms, the `reductions` algorithm also comes in two flavors: throwing or non throwing transformations.

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

These APIs can be used to reduce an initial value progressively or reduce into an initial value via mutation. In practice, a common use case for reductions is to mutate a collection by appending values.

```swift
characters.reductions(into: "") { $0.append($1) }
```

If the characters being produced asynchronously are `"a", "b", "c"`, then the iteration of the reductions is `"a", "ab", "abc"`.

Inclusive reductions do not have an initial value and therefore do not need an additional variations beyond the throwing and non throwing flavors. 

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

This is often used for scenarios like a running tally or other similar cases.

```swift
numbers.reductions { $0 + $1 }
```

In the above example, if the numbers are a sequence of `1, 2, 3, 4`, the produced values would be `1, 3, 6, 10`.

The `removeDuplicates()` and `removeDuplicates(by:)` APIs serve this purpose of removing duplicate values that occur. These are special case optimizations in the family of the reductions APIs. These algorithms test against the previous value and if the latest iteration of the base `AsyncSequence` is the same as the last it invokes `next()` again. The resulting `AsyncRemoveDuplicatesSequence` will ensure that no duplicate values occur next to each other. This should not be confused with only emitting unique new values; where each value is tested against a collected set of values.

```swift
extension AsyncSequence where Element: Equatable {
  public func removeDuplicates() -> AsyncRemoveDuplicatesSequence<Self>
}

extension AsyncSequence {
  public func removeDuplicates(
    by predicate: @escaping @Sendable (Element, Element) async -> Bool
  ) -> AsyncRemoveDuplicatesSequence<Self>

  public func removeDuplicates(
    by predicate: @escaping @Sendable (Element, Element) async throws -> Bool
  ) -> AsyncThrowingRemoveDuplicatesSequence<Self>
}
```

The `removeDuplicates` family comes in three variants. One variant is conditional upon the `Element` type being `Equatable`. This variation is a shorthand for writing `.removeDuplicates { $0 == $1 }`. The next variation is the closure version that allows for custom predicates to be applied. This algorithm allows for the cases where the elements themselves may not be equatable but portions of the element may be compared. Lastly is the variation that allows for comparison when the comparison method may throw.

## Detailed Design

#### Reductions

The exclusive reduction variants come in two distinct cases: non-throwing and throwing. These both have corresponding types to encompass that throwing behavior.

For non-throwing exclusive reductions, the element type of the sequence is the result of the reduction transform. `AsyncExclusiveReductionsSequence` will throw if the base asynchronous sequence throws, and will not throw if the base does not throws.

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
  
```

The sendability behavior of `AsyncExclusiveReductionsSequence` is such that when the base, base iterator, and element are `Sendable` then `AsyncExclusiveReductionsSequence` is `Sendable`.

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
  
```

#### Remove Duplicates

In the cases where the `Element` type is `Equatable` or the non-trowing predicate variant these utilize the type `AsyncRemoveDuplicatesSequence`. The throwing predicate variant uses `AsyncThrowingRemoveDuplicatesSequence`. Both of these types are conditionally `Sendable` when the base, base element, and base iterator are `Sendable`

The `AsyncRemoveDuplicatesSequence` will rethrow if the base asynchronous sequence throws and will not throw if the base asynchronous sequence does not throw.

```swift
public struct AsyncRemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(iterator: base.makeAsyncIterator(), predicate: predicate)
  }
}

extension AsyncRemoveDuplicatesSequence: Sendable
  where Base: Sendable, Base.Element: Sendable { }

```

The `AsyncThrowingRemoveDuplicatesSequence` will rethrow if the base asynchronous sequence throws and still may throw if the base asynchronous sequence does not throw due to the predicate having the potential of throwing.

```swift

public struct AsyncThrowingRemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async throws -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

extension AsyncThrowingRemoveDuplicatesSequence: Sendable
  where Base: Sendable, Base.Element: Sendable { }

```

## Alternatives Considered

One alternate name for `reductions` was to name it `scan`; however the naming from the Swift Algorithms package offers considerably more inference to the heritage of what family of functions this algorithm belongs to.

## Credits/Inspiration

This transformation function is a direct analog to the synchronous version [defined in the Swift Algorithms package](https://github.com/apple/swift-algorithms/blob/main/Guides/Reductions.md)

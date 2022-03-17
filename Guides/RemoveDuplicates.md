# RemoveDuplicates

* Author(s): [Kevin Perry](https://github.com/kperryua)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncRemoveDuplicatesSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestRemoveDuplicates.swift)
]

## Introduction

When processing values over time it is definitely possible that the same value may occur in a row. When the distinctness of the presence value is not needed it is useful to consider the values over time that are differing from the last. Particularly this can be expressed as removing duplicate values either in the case as they are directly `Equatable` or by a predicate. 

## Proposed Solution

The `removeDuplicates()` and `removeDuplicates(by:)` APIs serve this purpose of removing duplicate values that occur. These algorithms test against the previous value and if the latest iteration of the base `AsyncSequence` is the same as the last it invokes `next()` again. The resulting `AsyncRemoveDuplicatesSequence` will ensure that no duplicate values occur next to each other. This should not be confused with only emitting unique new values; where each value is tested against a collected set of values.

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
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }
  
extension AsyncRemoveDuplicatesSequence.Iterator: Sendable 
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }

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
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }
  
extension AsyncThrowingRemoveDuplicatesSequence.Iterator: Sendable 
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }

```

## Alternatives Considered

An alternative algorithm for uniqueness was considered but was discounted since it does not directly belong to this particular family of methods.

The name of this method could be considered to belong to the `filter` family and could refer directly to the repetitions. There is distinct merit to considering the name to be `filterRepetitions` or `removeRepetitions`. Likewise the terminology of `drop` also has merit. 

## Credits/Inspiration

The Combine framework has a [function for publishers](https://developer.apple.com/documentation/combine/publisher/removeduplicates()/) that performs a similar task.

# RemoveDuplicates

* Author(s): [Kevin Perry](https://github.com/kperryua)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncRemoveDuplicatesSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestRemoveDuplicates.swift)
]

## Introduction

## Proposed Solution

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

## Detailed Design

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

public struct AsyncThrowingRemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async throws -> Element?
  }
  
  public func makeAsyncIterator() -> Iterator
}

extension AsyncRemoveDuplicatesSequence: Sendable 
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }
  
extension AsyncRemoveDuplicatesSequence.Iterator: Sendable 
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }

extension AsyncThrowingRemoveDuplicatesSequence: Sendable 
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }
  
extension AsyncThrowingRemoveDuplicatesSequence.Iterator: Sendable 
  where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }

```

## Alternatives Considered

## Credits/Inspiration

The Combine framework has a [function for publishers](https://developer.apple.com/documentation/combine/publisher/removeduplicates()/) that performs a similar task.

# Joined

* Author(s): [Kevin Perry](https://github.com/kperryua)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncJoinedSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestJoin.swift)
]

## Introduction

## Proposed Solution

```swift
extension AsyncSequence where Element: AsyncSequence {
  public func joined<Separator: AsyncSequence>(
    separator: Separator
  ) -> AsyncJoinedSequence<Self, Separator>
}
```

## Detailed Design

```swift
public struct AsyncJoinedSequence<Base: AsyncSequence, Separator: AsyncSequence>: AsyncSequence 
  where Base.Element: AsyncSequence, Separator.Element == Base.Element.Element {
  public typealias Element = Base.Element.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Base.Element.Element?
  }

  public func makeAsyncIterator() -> Iterator
}

extension AsyncJoinedSequence: Sendable
  where 
    Base: Sendable, 
    Base.Element: Sendable, 
    Base.Element.Element: Sendable, 
    Base.AsyncIterator: Sendable, 
    Separator: Sendable, 
    Separator.AsyncIterator: Sendable, 
    Base.Element.AsyncIterator: Sendable { }
    
extension AsyncJoinedSequence.Iterator: Sendable
  where 
    Base: Sendable, 
    Base.Element: Sendable, 
    Base.Element.Element: Sendable, 
    Base.AsyncIterator: Sendable, 
    Separator: Sendable, 
    Separator.AsyncIterator: Sendable, 
    Base.Element.AsyncIterator: Sendable { }
```

## Alternatives Considered

## Credits/Inspiration

The Swift standard library has a [function on synchronous sequences](https://developer.apple.com/documentation/swift/sequence/1641166-joined) that performs a similar (but synchronous) task.

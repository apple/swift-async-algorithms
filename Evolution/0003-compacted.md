# Compacted

* Proposal: [SAA-0003](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0003-compacted.md)
* Authors: [Philippe Hausler](https://github.com/phausler)
* Status: **Accepted**

* Implementation: [Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncCompactedSequence.swift)
    [Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestCompacted.swift)

## Proposed Solution

Similar to the Swift Algorithms package we propose that a new method be added to `AsyncSequence` to fit this need.

```swift
extension AsyncSequence {
  public func compacted<Unwrapped>() -> AsyncCompactedSequence<Self, Unwrapped>
    where Element == Unwrapped?
}
```

This is equivalent to writing `.compactMap { $0 }` from a behavioral standpoint but is easier to reason about and is more efficient since it does not need to execute or store a closure.

## Detailed Design

The `AsyncCompactedSequence` type from an effects standpoint works just like `AsyncCompactMapSequence`. When the base asynchronous sequence throws, the iteration of `AsyncCompactedSequence` can throw. Likewise if the base does not throw then the iteration of `AsyncCompactedSequence` does not throw. This type is conditionally `Sendable` when the base, base element, and base iterator are `Sendable.

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

## Effect on API resilience

Compacted has a trivial implementation and is marked as `@frozen` and `@inlinable`. This removes the ability of this type and functions to be ABI resilient boundaries at the benefit of being highly optimizable.

## Alternatives considered

None; shy of potentially eliding this since the functionality is so trivial. However the utility of this function aides in ease of use and approachability along with parity with the Swift Algorithms package.

## Acknowledgments

This transformation function is a direct analog to the synchronous version [defined in the Swift Algorithms package](https://github.com/apple/swift-algorithms/blob/main/Guides/Compacted.md)

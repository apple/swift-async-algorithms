# Joined

* Author(s): [Kevin Perry](https://github.com/kperryua)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncJoinedSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestJoin.swift)
]

## Introduction

Concatenates an asynchronous sequence of asynchronous sequences that share an `Element` type together sequentially where the elements from the resulting asynchronous sequence are comprised in order from the elements of the first asynchronous sequence and then the second (and so on) or until an error occurs. Similar to `chain()`, except the number of asynchronous sequences to concatenate is not known up front.

Optionally allows inserting the elements of a separator asynchronous sequence in between each of the other sequences.

```swift
let sequenceOfURLs: AsyncSequence<URL> = ...
let sequenceOfLines = sequenceOfURLs.map { $0.lines }
let joinedWithSeparator = sequenceOfLines.joined(separator: ["===================="].async)

for try await lineOrSeparator in joinedWithSeparator {
  print(lineOrSeparator)
}
```

This example shows how an `AsyncSequence` of `URL`s can be turned into an `AsyncSequence` of the lines of each of those files in sequence, with a separator line in between each file.

## Proposed Solution

```swift
extension AsyncSequence where Element: AsyncSequence {
  public func joined() -> AsyncJoinedSequence<Self> {
    return AsyncJoinedSequence(self)
  }
}
```

```swift
extension AsyncSequence where Element: AsyncSequence {
  public func joined<Separator: AsyncSequence>(separator: Separator) -> AsyncJoinedBySeparatorSequence<Self, Separator> {
    return AsyncJoinedBySeparatorSequence(self, separator: separator)
  }
}
```

## Detailed Design

```swift
public struct AsyncJoinedSequence<Base: AsyncSequence>: AsyncSequence where Base.Element: AsyncSequence {
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
    Base.Element.AsyncIterator: Sendable { }
    
extension AsyncJoinedSequence.Iterator: Sendable
  where
    Base: Sendable,
    Base.Element: Sendable,
    Base.Element.Element: Sendable,
    Base.AsyncIterator: Sendable,
    Base.Element.AsyncIterator: Sendable { }
```

```swift
public struct AsyncJoinedBySeparatorSequence<Base: AsyncSequence, Separator: AsyncSequence>: AsyncSequence 
  where Base.Element: AsyncSequence, Separator.Element == Base.Element.Element {
  public typealias Element = Base.Element.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Base.Element.Element?
  }

  public func makeAsyncIterator() -> Iterator
}

extension AsyncJoinedBySeparatorSequence: Sendable
  where 
    Base: Sendable, 
    Base.Element: Sendable, 
    Base.Element.Element: Sendable, 
    Base.AsyncIterator: Sendable, 
    Separator: Sendable, 
    Separator.AsyncIterator: Sendable, 
    Base.Element.AsyncIterator: Sendable { }
    
extension AsyncJoinedBySeparatorSequence.Iterator: Sendable
  where 
    Base: Sendable, 
    Base.Element: Sendable, 
    Base.Element.Element: Sendable, 
    Base.AsyncIterator: Sendable, 
    Separator: Sendable, 
    Separator.AsyncIterator: Sendable, 
    Base.Element.AsyncIterator: Sendable { }
```

The resulting `AsyncJoinedSequence` or `AsyncJoinedBySeparatorSequence` type is an asynchronous sequence, with conditional conformance to `Sendable` when the arguments conform.

When any of the asynchronous sequences being joined together come to their end of iteration, the `Joined` sequence iteration proceeds to the separator asynchronous sequence, if any. When the separator asynchronous sequence terminates, or if no separator was specified, it proceeds on to the next asynchronous sequence. When the last asynchronous sequence reaches the end of iteration the `AsyncJoinedSequence` or `AsyncJoinedBySeparatorSequence` then ends its iteration. At any point in time if one of the comprising asynchronous sequences ever throws an error during iteration the `AsyncJoinedSequence` or `AsyncJoinedBySeparatorSequence` iteration will throw that error and end iteration.

## Future Directions

The Swift Algorithms package has [additional synchronous variants of `joined()`](https://github.com/apple/swift-algorithms/blob/main/Guides/Joined.md). It is conceivable to bring asynchronous variants of those over to `AsyncSequence`.

The variant that takes a single element as a separator is straightforward, but can be trivially replicated with `[element].async`. However, it may be beneficial for performance to reimplement this directly.

There is another variant that takes a closure that allows one to customize the separator based on the return value of a closure. That closure is passed each of the two consecutive asynchronous sequences (not the two neighboring elements in consecutive sequences). This variant arguably has the greatest utility when the sequence type conforms to `Collection`, allowing either the `count` or any arbitrary element to be obtained directly. With `AsyncSequence`, it is less likely that this function with provide a similar level of utility, so it has been omitted.

## Alternatives Considered

Because `joined()` is essentially identical to `flatMap { $0 }`, it was considered that this should be called `flatten()` instead. However, it is preferable to follow the lead of the Swift standard library's `joined()` method.

## Credits/Inspiration

The Swift standard library has functions on synchronous sequences ([`joined()`](https://developer.apple.com/documentation/swift/sequence/1641166-joined), [`joined(separator:)`](https://developer.apple.com/documentation/swift/sequence/2431985-joined)) that perform similar (but synchronous) tasks.

# Combine Latest

* Proposal: [SAA-0006](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0006-combineLatest.md)
* Authors: [Philippe Hausler](https://github.com/phausler)
* Status: **Accepted**


* Implementation: [[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/CombineLatest/AsyncCombineLatest2Sequence.swift), [Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/CombineLatest/AsyncCombineLatest3Sequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestCombineLatest.swift)]

* Decision Notes: 
* Bugs: 

## Introduction

Similar to the `zip` algorithm there is a need to combine the latest values from multiple input asynchronous sequences. Since `AsyncSequence` augments the concept of sequence with the characteristic of time it means that the composition of elements may not just be pairwise emissions but instead be temporal composition. This means that it is useful to emit a new tuple _when_ a value is produced. The `combineLatest` algorithm provides precisely that.

## Detailed Design

This algorithm combines the latest values produced from two or more asynchronous sequences into an asynchronous sequence of tuples.

```swift
let appleFeed = URL("http://www.example.com/ticker?symbol=AAPL").lines
let nasdaqFeed = URL("http://www.example.com/ticker?symbol=^IXIC").lines

for try await (apple, nasdaq) in combineLatest(appleFeed, nasdaqFeed) {
  print("AAPL: \(apple) NASDAQ: \(nasdaq)")
}
```

Given some sample inputs the following combined events can be expected.

| Timestamp   | appleFeed | nasdaqFeed | combined output               |                 
| ----------- | --------- | ---------- | ----------------------------- |
| 11:40 AM    | 173.91    |            |                               |
| 12:25 AM    |           | 14236.78   | AAPL: 173.91 NASDAQ: 14236.78 |
| 12:40 AM    |           | 14218.34   | AAPL: 173.91 NASDAQ: 14218.34 |
|  1:15 PM    | 173.00    |            | AAPL: 173.00 NASDAQ: 14218.34 |

This function family and the associated family of return types are prime candidates for variadic generics. Until that proposal is accepted, these will be implemented in terms of two- and three-base sequence cases.

```swift
public func combineLatest<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncCombineLatest2Sequence<Base1, Base2>

public func combineLatest<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(_ base1: Base1, _ base2: Base2, _ base3: Base3) -> AsyncCombineLatest3Sequence<Base1, Base2, Base3>

public struct AsyncCombineLatest2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: Sendable
  where
    Base1: Sendable, Base2: Sendable,
    Base1.Element: Sendable, Base2.Element: Sendable {
  public typealias Element = (Base1.Element, Base2.Element)

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

public struct AsyncCombineLatest3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
  where
    Base1: Sendable, Base2: Sendable, Base3: Sendable
    Base1.Element: Sendable, Base2.Element: Sendable, Base3.Element: Sendable {
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

```

The `combineLatest(_:...)` function takes two or more asynchronous sequences as arguments and produces an  `AsyncCombineLatestSequence` which is an asynchronous sequence.

Since the bases comprising the `AsyncCombineLatestSequence` must be iterated concurrently to produce the latest value, those sequences must be able to be sent to child tasks. This means that a prerequisite of the bases must be that the base asynchronous sequences, their iterators, and the elements they produce must all be `Sendable`. 

If any of the bases terminate before the first element is produced, then the `AsyncCombineLatestSequence` iteration can never be satisfied. So, if a base's iterator returns `nil` at the first iteration, then the `AsyncCombineLatestSequence` iterator immediately returns `nil` to signify a terminal state. In this particular case, any outstanding iteration of other bases will be cancelled. After the first element is produced ,this behavior is different since the latest values can still be satisfied by at least one base. This means that beyond the construction of the first tuple comprised of the returned elements of the bases, the terminal state of the `AsyncCombineLatestSequence` iteration will only be reached when all of the base iterations reach a terminal state.

The throwing behavior of `AsyncCombineLatestSequence` is that if any of the bases throw, then the composed asynchronous sequence throws on its iteration. If at any point (within the first iteration or afterwards), an error is thrown by any base, the other iterations are cancelled and the thrown error is immediately thrown to the consuming iteration.

### Naming

Since the inherent behavior of `combineLatest(_:...)` combines the latest values from multiple streams into a tuple the naming is intended to be quite literal. There are precedent terms of art in other frameworks and libraries (listed in the comparison section). Other naming takes the form of "withLatestFrom". This was disregarded since the "with" prefix is often most associated with the passing of a closure and some sort of contextual concept; `withUnsafePointer` or `withUnsafeContinuation` are prime examples.

### Comparison with other libraries

Combine latest often appears in libraries developed for processing events over time since the event ordering of a concept of "latest" only occurs when asynchrony is involved.

**ReactiveX** ReactiveX has an [API definition of CombineLatest](https://reactivex.io/documentation/operators/combinelatest.html) as a top level function for combining Observables.

**Combine** Combine has an [API definition of combineLatest](https://developer.apple.com/documentation/combine/publisher/combinelatest(_:)/) has an operator style method for combining Publishers.

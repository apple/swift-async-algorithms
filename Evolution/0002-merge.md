# Merge

* Proposal: [SAA-0002](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0002-merge.md)
* Authors: [Philippe Hausler](https://github.com/phausler)
* Status: **Accepted**

* Implementation: [[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Merge/AsyncMerge2Sequence.swift), [Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Merge/AsyncMerge3Sequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestMerge.swift)]
* Decision Notes: 
* Bugs: 

## Introduction

In the category of combinations of asynchronous sequences there are a few different potential behaviors. This category all take two or more `AsyncSequence` types and produce one `AsyncSequence`. One fundamental behavior is taking all values produced by the inputs and resuming the iteration of the singular downstream `AsyncSequence` with those values. This shape is called merge.

## Detailed Design

Merge takes two or more asynchronous sequences sharing the same element type and combines them into one singular asynchronous sequence of those elements.

```swift
let appleFeed = URL(string: "http://www.example.com/ticker?symbol=AAPL")!.lines.map { "AAPL: " + $0 }
let nasdaqFeed = URL(string:"http://www.example.com/ticker?symbol=^IXIC")!.lines.map { "^IXIC: " + $0 }

for try await ticker in merge(appleFeed, nasdaqFeed) {
  print(ticker)
}
```

Given some sample inputs the following merged events can be expected.

| Timestamp   | appleFeed | nasdaqFeed | merged output   |                 
| ----------- | --------- | ---------- | --------------- |
| 11:40 AM    | 173.91    |            | AAPL: 173.91    |
| 12:25 AM    |           | 14236.78   | ^IXIC: 14236.78 |
| 12:40 AM    |           | 14218.34   | ^IXIC: 14218.34 |
|  1:15 PM    | 173.00    |            | AAPL: 173.00    |

This function family and the associated family of return types are prime candidates for variadic generics. Until that proposal is accepted, these will be implemented in terms of two- and three-base sequence cases.

```swift
public func merge<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncMerge2Sequence<Base1, Base2>

public func merge<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(_ base1: Base1, _ base2: Base2, _ base3: Base3) -> AsyncMerge3Sequence<Base1, Base2, Base3>

public struct AsyncMerge2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: Sendable
  where
    Base1.Element == Base2.Element,
    Base1: Sendable, Base2: Sendable,
    Base1.Element: Sendable, Base2.Element: Sendable {
  public typealias Element = Base1.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

public struct AsyncMerge3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
  where
    Base1.Element == Base2.Element, Base1.Element == Base3.Element,
    Base1: Sendable, Base2: Sendable, Base3: Sendable
    Base1.Element: Sendable, Base2.Element: Sendable, Base3.Element: Sendable {
  public typealias Element = Base1.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

```

The `merge(_:...)` function takes two or more asynchronous sequences as arguments and produces an `AsyncMergeSequence` which is an asynchronous sequence.

Since the bases comprising the `AsyncMergeSequence` must be iterated concurrently to produce the latest value,  those sequences must be able to be sent to child tasks. This means that a prerequisite of the bases must be that the base asynchronous sequences, their iterators, and the elements they produce must be `Sendable`. 

When iterating a `AsyncMergeSequence`, the sequence terminates when all of the base asynchronous sequences terminate, since this means there is no potential for any further elements to be produced. 

The throwing behavior of `AsyncMergeSequence` is that if any of the bases throw, then the composed asynchronous sequence throws on its iteration. If at any point an error is thrown by any base, the other iterations are cancelled and the thrown error is immediately thrown to the consuming iteration.

### Naming

Since the inherent behavior of `merge(_:...)` merges values from multiple streams into a singular asynchronous sequence, the naming is intended to be quite literal. There are precedent terms of art in other frameworks and libraries (listed in the comparison section). Other naming takes the form of "withLatestFrom". This was disregarded since the "with" prefix is often most associated with the passing of a closure and some sort of contextual concept; `withUnsafePointer` or `withUnsafeContinuation` are prime examples.

### Comparison with other libraries

**ReactiveX** ReactiveX has an [API definition of Merge](https://reactivex.io/documentation/operators/merge.html) as a top level function for merging Observables.

**Combine** Combine has an [API definition of merge(with:)](https://developer.apple.com/documentation/combine/publisher/merge(with:)-7qt71/) as an operator style method for merging Publishers.

## Effect on API resilience

### `@frozen` and `@inlinable`

These types utilize rethrowing mechanisms that are awaiting an implementation in the compiler for supporting implementation based rethrows. So none of them are marked as frozen or marked as inlinable. This feature (discussed as `rethrows(unsafe)` or `rethrows(SourceOfRethrowyness)` has not yet been reviewed or implemented. The current implementation takes liberties with an internal protocol to accomplish this task. Future revisions will remove that protocol trick to replace it with proper rethrows semantics at the actual call site. The types are expected to be stable boundaries to prevent that workaround for the compilers yet to be supported rethrowing (or TaskGroup rethrowing) mechanisms. As soon as that feature is resolved; a more detailed investigation on performance impact of inlining and frozen should be done before 1.0.

## Alternatives considered

It was considered to have merge be shaped as an extension method on `AsyncSequence` however that infers a "primary-ness" of one `AsyncSequence` over another. Since the behavior of this as a global function (which infers no preference to one side or another) it was decided that having symmetry between the asynchronous version and the synchronous version inferred the right connotations.

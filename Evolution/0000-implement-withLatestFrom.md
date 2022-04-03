# Feature name

* Proposal: [NNNN](NNNN-filename.md)
* Authors: [Thibault Wittemberg](https://github.com/twittemb)
* Review Manager: TBD
* Status: **Awaiting implementation**

*During the review process, add the following fields as needed:*

* Implementation: [apple/swift-async-algorithms#NNNNN](https://github.com/apple/swift-async-algorithms/pull/NNNNN)
* Decision Notes: [Rationale](https://forums.swift.org/), [Additional Commentary](https://forums.swift.org/)
* Bugs: [NNNN](https://github.com/apple/swift-async-algorithms/issues)

## Introduction

There are several strategies when it comes to combining several sequences of events each having their own temporality. This proposal describes an operator that combines an async sequence values with the latest known values from other ones.

Swift forums thread: [[Pitch] withLatestFrom](https://forums.swift.org/t/pitch-withlatestfrom/56487/28)

## Motivation

Being able to combine values happening over time is a common practice in software engineering. The goal is to synchronize events from several sources by applying some strategies.

This is an area where reactive programming frameworks are particularly suited. Whether it is [Combine](https://developer.apple.com/documentation/combine), [RxSwift](https://github.com/ReactiveX/RxSwift) or [ReactiveCocoa](https://github.com/ReactiveCocoa/ReactiveSwift), they all provide operators that combine streams of events using some common patterns. 

The field of possibilities is generally summarized by `zip` and `combineLatest`.

### zip

`zip` combines elements from several streams and delivers groups of elements. The returned stream waits until all upstream streams have produced an element, then delivers the latest elements from each stream as a tuple.

That kind of operator can be used to synchronize elements from several concurrent works. A common usecase is to synchronize values coming from concurrent network calls.

The following example from the [zip guide](https://github.com/apple/swift-async-algorithms/blob/main/Guides/Zip.md) illustrates the synchronization mechanism in the case of two streams of stock values:


| Timestamp   | appleFeed | nasdaqFeed | combined output               |                 
| ----------- | --------- | ---------- | ----------------------------- |
| 11:40 AM    | 173.91    |            |                               |
| 12:25 AM    |           | 14236.78   | AAPL: 173.91 NASDAQ: 14236.78 |
| 12:40 AM    |           | 14218.34   |                               |
|  1:15 PM    | 173.00    |            | AAPL: 173.00 NASDAQ: 14218.34 |

### combineLatest

The `combineLatest` operator behaves in a similar way to `zip`, but while `zip` produces elements only when each of the zipped streams have produced an element, `combineLatest` produces an element whenever any of the source stream produces one.

The following example from the [combineLatest guide](https://github.com/apple/swift-async-algorithms/blob/main/Guides/CombineLatest.md) illustrates the synchronization mechanism in the case of two streams of stock values:


| Timestamp   | appleFeed | nasdaqFeed | combined output               |                 
| ----------- | --------- | ---------- | ----------------------------- |
| 11:40 AM    | 173.91    |            |                               |
| 12:25 AM    |           | 14236.78   | AAPL: 173.91 NASDAQ: 14236.78 |
| 12:40 AM    |           | 14218.34   | AAPL: 173.91 NASDAQ: 14218.34 |
|  1:15 PM    | 173.00    |            | AAPL: 173.00 NASDAQ: 14218.34 |


### When self should impose its pace!

With `zip` and `combineLatest` all streams have equal weight in the aggregation algorithm that forms the tuples. Input streams can be interchanged without changing the operator's behavior. We can see `zip` as an `AND` boolean operator and `combineLatest` as an `OR` boolean operator: in boolean algebra they are commutative properties.

There can be usecases where a particular stream should impose its pace to the others.

What if we want a new value of the tuple (`AAPL`, `NASDAQ`) to be produced **ONLY WHEN** the `appleFeed` produces an element?

Although `combineLatest` is close to the desired behavior, it is not exactly it: a new tuple will be produced also when `nasdaqFeed` produces a new element.

Following the stock example, the desired behavior would be:

| Timestamp   | appleFeed | nasdaqFeed | combined output               |                 
| ----------- | --------- | ---------- | ----------------------------- |
| 11:40 AM    | 173.91    |            |                               |
| 12:25 AM    |           | 14236.78   |                               |
| 12:40 AM    |           | 14218.34   |                               |
|  1:15 PM    | 173.00    |            | AAPL: 173.00 NASDAQ: 14218.34 |

Unlike `zip` and `combineLatest`, we cannot interchange the 2 feeds without changing the awaited behavior.

## Proposed solution

We propose to introduce an new operator that applies to `self` (self being an `AsyncSequence`), and that takes other AsyncSequences as parameters.

The temporary name for this operator is: `.withLatest(from:)`.

`.withLatest(from:)` combines elements from `self` with elements from other asynchronous sequences and delivers groups of elements as tuples. The returned `AsyncSequence` produces elements when `self` produces an element and groups it with the latest known elements from the other sequences to form the output tuples.


## Detailed design

This function family and the associated family of return types are prime candidates for variadic generics. Until that proposal is accepted, these will be implemented in terms of two- and three-base sequence cases.

```swift
public extension AsyncSequence {
  func withLatest<Other: AsyncSequence>(from other: Other) -> AsyncWithLatestFromSequence<Self, Other> {
    AsyncWithLatestFromSequence(self, other)
  }
  
  func withLatest<Other1: AsyncSequence, Other2: AsyncSequence>(from other1: Other1, _ other2: Other2) -> AsyncWithLatestFrom2Sequence<Self, Other> {
    AsyncWithLatestFrom2Sequence(self, other1, other2)
  }
}

public struct AsyncWithLatestFromSequence<Base: AsyncSequence, Other: AsyncSequence> {
  public typealias Element = (Base.Element, Other.Element)
  public typealias AsyncIterator = Iterator

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

public struct AsyncWithLatestFrom2Sequence<Base: AsyncSequence, Other1: AsyncSequence, Other2: AsyncSequence> {
  public typealias Element = (Base.Element, Other1.Element, Other2.Element)
  public typealias AsyncIterator = Iterator

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}
```

The `withLatest(from:...)` function takes one or two asynchronous sequences as arguments and produces an `AsyncWithLatestFromSequence`/`AsyncWithLatestFrom2Sequence` which is an asynchronous sequence.

As we must know the latest elements from `others` to form the output tuple when `self` produces a new element, we must iterate over `others` asynchronously using Tasks.

For the first iteration of `AsyncWithLatestFromSequence` to produce an element, `AsyncWithLatestFromSequence` will wait for `self` and `others` to produce a first element.

Each subsequent iteration of an `AsyncWithLatestFromSequence` will wait for `self` to produce an element.

If self` terminates by returning nil from its iteration, the `AsyncWithLatestFromSequence` iteration is immediately considered unsatisfiable and returns nil and all iterations of other bases will be cancelled.

If `others` terminates by returning nil from their iteration, the `AsyncWithLatestFromSequence` iteration continues by agregating elements from `self` and last known elements from `others`.

If any iteration of `self` or `others` throws an error, then the `others` iterations are cancelled and the produced error is rethrown, terminating the iteration.

The source of throwing of `AsyncWithLatestFromSequence` is determined by `Self` and `Others`. That means that if `self` or any `other` can throw an error then the iteration of the `AsyncWithLatestFromSequence` can throw. If `self` and `others` cannot throw, then the `AsyncWithLatestFromSequence` cannot throw.

## Effect on API resilience

None.

## Alternatives names

Those alternate names were suggested:

- `zip(sampling: other1, other2, atRateOf: self)`
- `zip(other1, other2, elementOn: .newElementFrom(self))`
- `self.zipWhen(other1, other2)`

## Comparison with other libraries

[RxSwift](https://github.com/ReactiveX/RxSwift/blob/main/RxSwift/Observables/WithLatestFrom.swift) provides an implementation of such an operator under the name `withLatestFrom` ([RxMarble](https://rxmarbles.com/#withLatestFrom))

## Acknowledgments

Thanks to everyone on the forum for giving great feedback.

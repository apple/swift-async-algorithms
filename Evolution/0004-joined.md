# Joined

* Proposal: [SAA-0004](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0004-joined.md)
* Authors: [Philippe Hausler](https://github.com/phausler)
* Review Manager: [Franz Busch](https://github.com/FranzBusch)
* Status: **Accepted**

* Implementation: [[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncJoinedSequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestJoin.swift)]
* Decision Notes: 
* Bugs: 

## Introduction

The `joined()` and `joined(separator:)` algorithms on `AsyncSequence`s provide APIs to concatenate an `AsyncSequence` of `AsyncSequence`s.

```swift
extension AsyncSequence where Element: AsyncSequence {
  public func joined() -> AsyncJoinedSequence<Self>
}

extension AsyncSequence where Element: AsyncSequence {
  public func joined<Separator: AsyncSequence>(separator: Separator) -> AsyncJoinedBySeparatorSequence<Self, Separator>
}
```

## Detailed Design

These algorithms iterate over the elements of each `AsyncSequence` one bye one, i.e. only after the iteration of one `AsyncSequence` has finished the next one will be started.

```swift
 let appleFeed = URL("http://www.example.com/ticker?symbol=AAPL").lines
 let nasdaqFeed = URL("http://www.example.com/ticker?symbol=^IXIC").lines

 for try await line in [appleFeed, nasdaqFeed].async.joined() {
   print("\(line)")
 }
 ```

 Given some sample inputs the following combined events can be expected.

 | Timestamp   | appleFeed | nasdaqFeed | output                        |                 
 | ----------- | --------- | ---------- | ----------------------------- |
 | 11:40 AM    | 173.91    |            | 173.91                        |
 | 12:25 AM    |           | 14236.78   |                               |
 | 12:40 AM    |           | 14218.34   |                               |
 |  1:15 PM    | 173.00    |            | 173.00                        |
 |  1:15 PM    |           |            | 14236.78                      |
 |  1:15 PM    |           |            | 14218.34                      |


The `joined()` and `joined(separator:)` methods are available on `AsyncSequence`s with elements that are `AsyncSequence`s themselves and produce either an `AsyncJoinedSequence` or an `AsyncJoinedBySeparatorSequence`. 

As soon as an inner `AsyncSequence` returns `nil` the algorithm continues with iterating the next inner `AsyncSequence`.

The throwing behaviour of `AsyncJoinedSequence` and `AsyncJoinedBySeparatorSequence` is that if any of the inner `AsyncSequence`s throws, then the composed sequence throws on its iteration.

### Naming

The naming follows to current method naming of the standard library's [`joined`](https://developer.apple.com/documentation/swift/array/joined(separator:)-7uber) method.
Prior art in the reactive community often names this method `concat`; however, we think that an alignment with the current method on `Sequence` is better.

### Comparison with other libraries

**ReactiveX** ReactiveX has an [API definition of Concat](https://reactivex.io/documentation/operators/concat.html) as a top level function for concatenating Observables.

**Combine** Combine has an [API definition of append](https://developer.apple.com/documentation/combine/publisher/append(_:)-5yh02) which offers similar functionality but limited to concatenating two individual `Publisher`s.

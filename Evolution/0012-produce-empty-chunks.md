# Produce Empty Chunks

* Proposal: [0012](0012-produce-empty-chunks.md)
* Author: [Rick Newton-Rogers](https://github.com/rnro)
* Review Manager: TBD
* Status: **Implemented**

* Implementation:
  [Source](https://github.com/rnewtonrogers/swift-async-algorithms/blob/allow_empty_chunks/Sources/AsyncAlgorithms/AsyncChunksOfCountOrSignalSequence.swift) | 
  [Tests](https://github.com/rnewtonrogers/swift-async-algorithms/blob/allow_empty_chunks/Tests/AsyncAlgorithmsTests/TestChunk.swift)

## Introduction

At the moment it is possible to use a signal `AsyncSequence` to provide marks at which elements of a primary 
`AsyncSequence` should be 'chunked' into collections. However if one or more signals arrive when there are no elements 
from the primary sequence to vend as output then they will be ignored.

## Motivation

As noted in [a GitHub Issue](https://github.com/apple/swift-async-algorithms/issues/247) it could be useful to output empty 
chunks in the outlined case to provide information of a lack of activity on the primary sequence. This would likely be 
particularly useful when combined with a timer as a signaling source.

## Proposed solution

Modify the API of the `AsyncSequence` `chunks` and `chunked` extensions to allow specifying of a new parameter 
(`produceEmptyChunks`) which determines if the output sequence produces empty chunks. The new parameter will retain the 
previous behavior by default.

## Detailed design

The modified API will look as follows:
```swift
extension AsyncSequence {
  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type of a given count or when a signal `AsyncSequence` produces an element.
  public func chunks<Signal, Collected: RangeReplaceableCollection>(ofCount count: Int, or signal: Signal, into: Collected.Type, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: count, signal: signal, produceEmptyChunks: produceEmptyChunks)
  }

  /// Creates an asynchronous sequence that creates chunks of a given count or when a signal `AsyncSequence` produces an element.
  public func chunks<Signal>(ofCount count: Int, or signal: Signal, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal> {
      chunks(ofCount: count, or: signal, into: [Element].self, produceEmptyChunks: produceEmptyChunks)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type when a signal `AsyncSequence` produces an element.
  public func chunked<Signal, Collected: RangeReplaceableCollection>(by signal: Signal, into: Collected.Type, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: nil, signal: signal, produceEmptyChunks: produceEmptyChunks)
  }

  /// Creates an asynchronous sequence that creates chunks when a signal `AsyncSequence` produces an element.
  public func chunked<Signal>(by signal: Signal, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal> {
      chunked(by: signal, into: [Element].self, produceEmptyChunks: produceEmptyChunks)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type of a given count or when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunks<C: Clock, Collected: RangeReplaceableCollection>(ofCount count: Int, or timer: AsyncTimerSequence<C>, into: Collected.Type, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: count, signal: timer, produceEmptyChunks: produceEmptyChunks)
  }

  /// Creates an asynchronous sequence that creates chunks of a given count or when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunks<C: Clock>(ofCount count: Int, or timer: AsyncTimerSequence<C>, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
      chunks(ofCount: count, or: timer, into: [Element].self, produceEmptyChunks: produceEmptyChunks)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(by timer: AsyncTimerSequence<C>, into: Collected.Type, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: nil, signal: timer, produceEmptyChunks: produceEmptyChunks)
  }

  /// Creates an asynchronous sequence that creates chunks when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunked<C: Clock>(by timer: AsyncTimerSequence<C>, produceEmptyChunks: Bool = false) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
      chunked(by: timer, into: [Element].self, produceEmptyChunks: produceEmptyChunks)
  }
}
```
The previous API will be marked as deprecated and `@_disfavoredOverload` to avoid ambiguity with the new versions.


## Effect on API resilience

This change is API-safe due to the default value but ABI-unsafe.

## Alternatives considered

- Providing a config struct to future-proof the API against further changes in the future was rejected because it 
seems to add overhead defending against an unlikely event.
- Providing entirely new API without deprecating the old one was ruled out to avoid an explosion in API complexity 
which increases maintenance burden and reduces readability of code.

## Acknowledgments

- [@tachyonics](https://github.com/tachyonics) for the initial GitHub issue describing the requirement.

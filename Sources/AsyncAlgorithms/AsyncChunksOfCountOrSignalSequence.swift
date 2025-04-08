//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequence {
  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type of a given count or when a signal `AsyncSequence` produces an element.
  @available(AsyncAlgorithms 1.0, *)
  public func chunks<Signal, Collected: RangeReplaceableCollection>(
    ofCount count: Int,
    or signal: Signal,
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: count, signal: signal)
  }

  /// Creates an asynchronous sequence that creates chunks of a given count or when a signal `AsyncSequence` produces an element.
  @available(AsyncAlgorithms 1.0, *)
  public func chunks<Signal>(
    ofCount count: Int,
    or signal: Signal
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal> {
    chunks(ofCount: count, or: signal, into: [Element].self)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type when a signal `AsyncSequence` produces an element.
  @available(AsyncAlgorithms 1.0, *)
  public func chunked<Signal, Collected: RangeReplaceableCollection>(
    by signal: Signal,
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: nil, signal: signal)
  }

  /// Creates an asynchronous sequence that creates chunks when a signal `AsyncSequence` produces an element.
  @available(AsyncAlgorithms 1.0, *)
  public func chunked<Signal>(by signal: Signal) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal> {
    chunked(by: signal, into: [Element].self)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type of a given count or when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunks<C: Clock, Collected: RangeReplaceableCollection>(
    ofCount count: Int,
    or timer: AsyncTimerSequence<C>,
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: count, signal: timer)
  }

  /// Creates an asynchronous sequence that creates chunks of a given count or when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunks<C: Clock>(
    ofCount count: Int,
    or timer: AsyncTimerSequence<C>
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
    chunks(ofCount: count, or: timer, into: [Element].self)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(
    by timer: AsyncTimerSequence<C>,
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: nil, signal: timer)
  }

  /// Creates an asynchronous sequence that creates chunks when an `AsyncTimerSequence` fires.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func chunked<C: Clock>(
    by timer: AsyncTimerSequence<C>
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
    chunked(by: timer, into: [Element].self)
  }
}

/// An `AsyncSequence` that chunks elements into collected `RangeReplaceableCollection` instances by either count or a signal from another `AsyncSequence`.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncChunksOfCountOrSignalSequence<
  Base: AsyncSequence,
  Collected: RangeReplaceableCollection,
  Signal: AsyncSequence
>: AsyncSequence, Sendable
where
  Collected.Element == Base.Element,
  Base: Sendable,
  Signal: Sendable,
  Base.Element: Sendable,
  Signal.Element: Sendable
{

  public typealias Element = Collected

  enum Either {
    case element(Base.Element)
    case terminal
    case signal
  }

  /// The iterator for a `AsyncChunksOfCountOrSignalSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {
    typealias EitherMappedBase = AsyncMapSequence<Base, Either>
    typealias EitherMappedSignal = AsyncMapSequence<Signal, Either>
    typealias ChainedBase = AsyncChain2Sequence<EitherMappedBase, AsyncSyncSequence<[Either]>>
    typealias Merged = AsyncMerge2Sequence<ChainedBase, EitherMappedSignal>

    let count: Int?
    var iterator: Merged.AsyncIterator
    var terminated = false

    init(iterator: Merged.AsyncIterator, count: Int?) {
      self.count = count
      self.iterator = iterator
    }

    public mutating func next() async rethrows -> Collected? {
      guard !terminated else {
        return nil
      }
      var result: Collected?
      while let next = try await iterator.next() {
        switch next {
        case .element(let element):
          if result == nil {
            result = Collected()
          }
          result!.append(element)
          if result?.count == count {
            return result
          }
        case .terminal:
          terminated = true
          return result
        case .signal:
          if result != nil {
            return result
          }
        }
      }
      return result
    }
  }

  let base: Base
  let signal: Signal
  let count: Int?
  init(_ base: Base, count: Int?, signal: Signal) {
    if let count = count {
      precondition(count > 0)
    }

    self.base = base
    self.count = count
    self.signal = signal
  }

  public func makeAsyncIterator() -> Iterator {

    return Iterator(
      iterator: merge(
        chain(base.map { Either.element($0) }, [.terminal].async),
        signal.map { _ in Either.signal }
      ).makeAsyncIterator(),
      count: count
    )
  }
}

@available(*, unavailable)
extension AsyncChunksOfCountOrSignalSequence.Iterator: Sendable {}

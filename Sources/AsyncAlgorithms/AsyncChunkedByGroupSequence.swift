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
  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection`
  /// type by testing if elements belong in the same group.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func chunked<Collected: RangeReplaceableCollection>(
    into: Collected.Type,
    by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool
  ) -> AsyncChunkedByGroupSequence<Self, Collected> where Collected.Element == Element {
    AsyncChunkedByGroupSequence(self, grouping: belongInSameGroup)
  }

  /// Creates an asynchronous sequence that creates chunks by testing if elements belong in the same group.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func chunked(
    by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool
  ) -> AsyncChunkedByGroupSequence<Self, [Element]> {
    chunked(into: [Element].self, by: belongInSameGroup)
  }
}

/// An `AsyncSequence` that chunks by testing if two elements belong to the same group.
///
/// Group chunks are determined by passing two consecutive elements to a closure which tests
/// whether they are in the same group. When the `AsyncChunkedByGroupSequence` iterator
/// receives the first element from the base sequence, it will immediately be added to a group. When
/// it receives the second item, it tests whether the previous item and the current item belong to the
/// same group. If they are not in the same group, then the iterator emits the first item's group and a
/// new group is created containing the second item. Items declared to be in the same group
/// accumulate until a new group is declared, or the iterator finds the end of the base sequence.
/// When the base sequence terminates, the final group is emitted. If the base sequence throws an
/// error, `AsyncChunkedByGroupSequence` will rethrow that error immediately and discard
/// any current group.
///
///      let numbers = [10, 20, 30, 10, 40, 40, 10, 20].async
///      let chunks = numbers.chunked { $0 <= $1 }
///      for await numberChunk in chunks {
///        print(numberChunk)
///      }
///      // prints
///      // [10, 20, 30]
///      // [10, 40, 40]
///      // [10, 20]
@available(AsyncAlgorithms 1.0, *)
public struct AsyncChunkedByGroupSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection>: AsyncSequence
where Collected.Element == Base.Element {
  public typealias Element = Collected

  /// The iterator for a `AsyncChunkedByGroupSequence` instance.
  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let grouping: @Sendable (Base.Element, Base.Element) -> Bool

    @usableFromInline
    init(base: Base.AsyncIterator, grouping: @escaping @Sendable (Base.Element, Base.Element) -> Bool) {
      self.base = base
      self.grouping = grouping
    }

    @usableFromInline
    var hangingNext: Base.Element?

    @inlinable
    public mutating func next() async rethrows -> Collected? {
      var firstOpt = hangingNext
      if firstOpt == nil {
        firstOpt = try await base.next()
      } else {
        hangingNext = nil
      }

      guard let first = firstOpt else {
        return nil
      }

      var result: Collected = .init()
      result.append(first)

      var prev = first
      while let next = try await base.next() {
        guard grouping(prev, next) else {
          hangingNext = next
          break
        }
        result.append(next)
        prev = next
      }
      return result
    }
  }

  @usableFromInline
  let base: Base

  @usableFromInline
  let grouping: @Sendable (Base.Element, Base.Element) -> Bool

  @usableFromInline
  init(_ base: Base, grouping: @escaping @Sendable (Base.Element, Base.Element) -> Bool) {
    self.base = base
    self.grouping = grouping
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), grouping: grouping)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncChunkedByGroupSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncChunkedByGroupSequence.Iterator: Sendable {}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@available(AsyncAlgorithms 1.0, *)
extension Sequence {
  /// An asynchronous sequence containing the same elements as this sequence,
  /// but on which operations, such as `map` and `filter`, are
  /// implemented asynchronously.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public var async: AsyncSyncSequence<Self> {
    AsyncSyncSequence(self)
  }
}

/// An asynchronous sequence composed from a synchronous sequence.
///
/// Asynchronous lazy sequences can be used to interface existing or pre-calculated
/// data to interoperate with other asynchronous sequences and algorithms based on
/// asynchronous sequences.
///
/// This functions similarly to `LazySequence` by accessing elements sequentially
/// in the iterator's `next()` method.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncSyncSequence<Base: Sequence>: AsyncSequence {
  public typealias Element = Base.Element

  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var iterator: Base.Iterator?

    @usableFromInline
    init(_ iterator: Base.Iterator) {
      self.iterator = iterator
    }

    @inlinable
    public mutating func next() async -> Base.Element? {
      guard !Task.isCancelled, let value = iterator?.next() else {
        iterator = nil
        return nil
      }
      return value
    }
  }

  @usableFromInline
  let base: Base

  @usableFromInline
  init(_ base: Base) {
    self.base = base
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeIterator())
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncSyncSequence: Sendable where Base: Sendable {}

@available(*, unavailable)
extension AsyncSyncSequence.Iterator: Sendable {}

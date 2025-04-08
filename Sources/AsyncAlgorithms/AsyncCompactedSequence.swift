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
extension AsyncSequence {
  /// Returns a new `AsyncSequence` that iterates over every non-nil element from the
  /// original `AsyncSequence`.
  ///
  /// Produces the same result as `c.compactMap { $0 }`.
  ///
  /// - Returns: An `AsyncSequence` where the element is the unwrapped original
  ///   element and iterates over every non-nil element from the original
  ///   `AsyncSequence`.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func compacted<Unwrapped>() -> AsyncCompactedSequence<Self, Unwrapped>
  where Element == Unwrapped? {
    AsyncCompactedSequence(self)
  }
}

/// An `AsyncSequence` that iterates over every non-nil element from the original
/// `AsyncSequence`.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncCompactedSequence<Base: AsyncSequence, Element>: AsyncSequence
where Base.Element == Element? {

  @usableFromInline
  let base: Base

  @inlinable
  init(_ base: Base) {
    self.base = base
  }

  /// The iterator for an `AsyncCompactedSequence` instance.
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var base: Base.AsyncIterator

    @inlinable
    init(_ base: Base.AsyncIterator) {
      self.base = base
    }

    @inlinable
    public mutating func next() async rethrows -> Element? {
      while let wrapped = try await base.next() {
        guard let some = wrapped else { continue }
        return some
      }
      return nil
    }
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator())
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncCompactedSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncCompactedSequence.Iterator: Sendable {}

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
  /// An `AsyncSequence` that iterates over the adjacent pairs of the original
  /// original `AsyncSequence`.
  ///
  /// ```
  /// for await (first, second) in (1...5).async.adjacentPairs() {
  ///    print("First: \(first), Second: \(second)")
  /// }
  ///
  /// // First: 1, Second: 2
  /// // First: 2, Second: 3
  /// // First: 3, Second: 4
  /// // First: 4, Second: 5
  /// ```
  ///
  /// - Returns: An `AsyncSequence` where the element is a tuple of two adjacent elements
  ///   or the original `AsyncSequence`.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func adjacentPairs() -> AsyncAdjacentPairsSequence<Self> {
    AsyncAdjacentPairsSequence(self)
  }
}

/// An `AsyncSequence` that iterates over the adjacent pairs of the original
/// `AsyncSequence`.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncAdjacentPairsSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = (Base.Element, Base.Element)

  @usableFromInline
  let base: Base

  @inlinable
  init(_ base: Base) {
    self.base = base
  }

  /// The iterator for an `AsyncAdjacentPairsSequence` instance.
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    public typealias Element = (Base.Element, Base.Element)

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    internal var previousElement: Base.Element?

    @inlinable
    init(_ base: Base.AsyncIterator) {
      self.base = base
    }

    @inlinable
    public mutating func next() async rethrows -> (Base.Element, Base.Element)? {
      if previousElement == nil {
        previousElement = try await base.next()
      }

      guard let previous = previousElement, let next = try await base.next() else {
        return nil
      }

      previousElement = next
      return (previous, next)
    }
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator())
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncAdjacentPairsSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncAdjacentPairsSequence.Iterator: Sendable {}

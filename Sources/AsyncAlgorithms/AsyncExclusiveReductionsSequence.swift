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
  /// Returns an asynchronous sequence containing the accumulated results of combining the
  /// elements of the asynchronous sequence using the given closure.
  ///
  /// This can be seen as applying the reduce function to each element and
  /// providing the initial value followed by these results as an asynchronous sequence.
  ///
  /// - Parameters:
  ///   - initial: The value to use as the initial value.
  ///   - transform: A closure that combines the previously-reduced result and
  ///     the next element in the receiving asynchronous sequence, which it returns.
  /// - Returns: An asynchronous sequence of the initial value followed by the reduced
  ///   elements.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func reductions<Result>(
    _ initial: Result,
    _ transform: @Sendable @escaping (Result, Element) async -> Result
  ) -> AsyncExclusiveReductionsSequence<Self, Result> {
    reductions(into: initial) { result, element in
      result = await transform(result, element)
    }
  }

  /// Returns an asynchronous sequence containing the accumulated results of combining the
  /// elements of the asynchronous sequence using the given closure.
  ///
  /// This can be seen as applying the reduce function to each element and
  /// providing the initial value followed by these results as an asynchronous sequence.
  ///
  /// - Parameters:
  ///   - initial: The value to use as the initial value.
  ///   - transform: A closure that combines the previously-reduced result and
  ///     the next element in the receiving asynchronous sequence, mutating the
  ///     previous result instead of returning a value.
  /// - Returns: An asynchronous sequence of the initial value followed by the reduced
  ///   elements.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func reductions<Result>(
    into initial: Result,
    _ transform: @Sendable @escaping (inout Result, Element) async -> Void
  ) -> AsyncExclusiveReductionsSequence<Self, Result> {
    AsyncExclusiveReductionsSequence(self, initial: initial, transform: transform)
  }
}

/// An asynchronous sequence of applying a transform to the element of an asynchronous sequence and the
/// previously transformed result.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncExclusiveReductionsSequence<Base: AsyncSequence, Element> {
  @usableFromInline
  let base: Base

  @usableFromInline
  let initial: Element

  @usableFromInline
  let transform: @Sendable (inout Element, Base.Element) async -> Void

  @inlinable
  init(_ base: Base, initial: Element, transform: @Sendable @escaping (inout Element, Base.Element) async -> Void) {
    self.base = base
    self.initial = initial
    self.transform = transform
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncExclusiveReductionsSequence: AsyncSequence {
  /// The iterator for an `AsyncExclusiveReductionsSequence` instance.
  @available(AsyncAlgorithms 1.0, *)
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var iterator: Base.AsyncIterator

    @usableFromInline
    var current: Element?

    @usableFromInline
    let transform: @Sendable (inout Element, Base.Element) async -> Void

    @inlinable
    init(
      _ iterator: Base.AsyncIterator,
      initial: Element,
      transform: @Sendable @escaping (inout Element, Base.Element) async -> Void
    ) {
      self.iterator = iterator
      self.current = initial
      self.transform = transform
    }

    @inlinable
    public mutating func next() async rethrows -> Element? {
      guard var result = current else { return nil }
      let value = try await iterator.next()
      guard let value = value else {
        current = nil
        return nil
      }
      await transform(&result, value)
      current = result
      return result
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator(), initial: initial, transform: transform)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncExclusiveReductionsSequence: Sendable where Base: Sendable, Element: Sendable {}

@available(*, unavailable)
extension AsyncExclusiveReductionsSequence.Iterator: Sendable {}

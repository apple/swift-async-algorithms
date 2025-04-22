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
  /// elements of the asynchronous sequence using the given error-throwing closure.
  ///
  /// This can be seen as applying the reduce function to each element and
  /// providing the initial value followed by these results as an asynchronous sequence.
  ///
  /// - Parameters:
  ///   - initial: The value to use as the initial value.
  ///   - transform: A closure that combines the previously reduced result and
  ///     the next element in the receiving asynchronous sequence and returns
  ///     the result. If the closure throws an error, the sequence throws.
  /// - Returns: An asynchronous sequence of the initial value followed by the reduced
  ///   elements.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func reductions<Result>(
    _ initial: Result,
    _ transform: @Sendable @escaping (Result, Element) async throws -> Result
  ) -> AsyncThrowingExclusiveReductionsSequence<Self, Result> {
    reductions(into: initial) { result, element in
      result = try await transform(result, element)
    }
  }

  /// Returns an asynchronous sequence containing the accumulated results of combining the
  /// elements of the asynchronous sequence using the given error-throwing closure.
  ///
  /// This can be seen as applying the reduce function to each element and
  /// providing the initial value followed by these results as an asynchronous sequence.
  ///
  /// - Parameters:
  ///   - initial: The value to use as the initial value.
  ///   - transform: A closure that combines the previously reduced result and
  ///     the next element in the receiving asynchronous sequence, mutating the
  ///     previous result instead of returning a value. If the closure throws an
  ///     error, the sequence throws.
  /// - Returns: An asynchronous sequence of the initial value followed by the reduced
  ///   elements.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func reductions<Result>(
    into initial: Result,
    _ transform: @Sendable @escaping (inout Result, Element) async throws -> Void
  ) -> AsyncThrowingExclusiveReductionsSequence<Self, Result> {
    AsyncThrowingExclusiveReductionsSequence(self, initial: initial, transform: transform)
  }
}

/// An asynchronous sequence of applying an error-throwing transform to the element of
/// an asynchronous sequence and the previously transformed result.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncThrowingExclusiveReductionsSequence<Base: AsyncSequence, Element> {
  @usableFromInline
  let base: Base

  @usableFromInline
  let initial: Element

  @usableFromInline
  let transform: @Sendable (inout Element, Base.Element) async throws -> Void

  @inlinable
  init(
    _ base: Base,
    initial: Element,
    transform: @Sendable @escaping (inout Element, Base.Element) async throws -> Void
  ) {
    self.base = base
    self.initial = initial
    self.transform = transform
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncThrowingExclusiveReductionsSequence: AsyncSequence {
  /// The iterator for an `AsyncThrowingExclusiveReductionsSequence` instance.
  @available(AsyncAlgorithms 1.0, *)
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var iterator: Base.AsyncIterator

    @usableFromInline
    var current: Element?

    @usableFromInline
    let transform: @Sendable (inout Element, Base.Element) async throws -> Void

    @inlinable
    init(
      _ iterator: Base.AsyncIterator,
      initial: Element,
      transform: @Sendable @escaping (inout Element, Base.Element) async throws -> Void
    ) {
      self.iterator = iterator
      self.current = initial
      self.transform = transform
    }

    @inlinable
    public mutating func next() async throws -> Element? {
      guard var result = current else { return nil }
      let value = try await iterator.next()
      guard let value = value else {
        current = nil
        return nil
      }
      do {
        try await transform(&result, value)
        current = result
        return result
      } catch {
        current = nil
        throw error
      }
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator(), initial: initial, transform: transform)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncThrowingExclusiveReductionsSequence: Sendable where Base: Sendable, Element: Sendable {}

@available(*, unavailable)
extension AsyncThrowingExclusiveReductionsSequence.Iterator: Sendable {}

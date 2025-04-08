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
  /// ```
  /// let runningTotal = [1, 2, 3, 4].async.reductions(+)
  /// print(await Array(runningTotal))
  ///
  /// // prints [1, 3, 6, 10]
  /// ```
  ///
  /// - Parameter transform: A closure that combines the previously reduced
  ///   result and the next element in the receiving sequence. If the closure
  ///     throws an error, the sequence throws.
  /// - Returns: An asynchronous sequence of the reduced elements.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func reductions(
    _ transform: @Sendable @escaping (Element, Element) async throws -> Element
  ) -> AsyncThrowingInclusiveReductionsSequence<Self> {
    AsyncThrowingInclusiveReductionsSequence(self, transform: transform)
  }
}

/// An asynchronous sequence containing the accumulated results of combining the
/// elements of the asynchronous sequence using a given error-throwing closure.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncThrowingInclusiveReductionsSequence<Base: AsyncSequence> {
  @usableFromInline
  let base: Base

  @usableFromInline
  let transform: @Sendable (Base.Element, Base.Element) async throws -> Base.Element

  @inlinable
  init(_ base: Base, transform: @Sendable @escaping (Base.Element, Base.Element) async throws -> Base.Element) {
    self.base = base
    self.transform = transform
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncThrowingInclusiveReductionsSequence: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncThrowingInclusiveReductionsSequence` instance.
  @available(AsyncAlgorithms 1.0, *)
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    internal var iterator: Base.AsyncIterator?

    @usableFromInline
    internal var element: Base.Element?

    @usableFromInline
    internal let transform: @Sendable (Base.Element, Base.Element) async throws -> Base.Element

    @inlinable
    init(
      _ iterator: Base.AsyncIterator,
      transform: @Sendable @escaping (Base.Element, Base.Element) async throws -> Base.Element
    ) {
      self.iterator = iterator
      self.transform = transform
    }

    @inlinable
    public mutating func next() async throws -> Base.Element? {
      guard let previous = element else {
        element = try await iterator?.next()
        return element
      }
      guard let next = try await iterator?.next() else { return nil }
      do {
        element = try await transform(previous, next)
      } catch {
        iterator = nil
        throw error
      }
      return element
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator(), transform: transform)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncThrowingInclusiveReductionsSequence: Sendable where Base: Sendable {}

@available(*, unavailable)
extension AsyncThrowingInclusiveReductionsSequence.Iterator: Sendable {}

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

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension AsyncSequence {
  /// Returns an asynchronous sequence containing the accumulated results of combining the
  /// elements of the asynchronous sequence using the given closure.
  ///
  /// This can be seen as applying the reduce function to each element and
  /// producing an asynchronous sequence consisting of the initial value followed
  /// by these results.
  ///
  /// ```
  /// let runningTotal = [1, 2, 3, 4].async.reductions(+)
  /// print(await Array(runningTotal))
  ///
  /// // prints [1, 3, 6, 10]
  /// ```
  ///
  /// - Parameter transform: A closure that combines the previously reduced
  ///   result and the next element in the receiving sequence, and returns
  ///   the result.
  /// - Returns: An asynchronous sequence of the reduced elements.
  @inlinable
  public func reductions(
    _ transform: @Sendable @escaping (Element, Element) async -> Element
  ) -> AsyncInclusiveReductionsSequence<Self> {
    AsyncInclusiveReductionsSequence(self, transform: transform)
  }
}

/// An asynchronous sequence containing the accumulated results of combining the
/// elements of the asynchronous sequence using a given closure.
@frozen
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct AsyncInclusiveReductionsSequence<Base: AsyncSequence> {
  @usableFromInline
  let base: Base

  @usableFromInline
  let transform: @Sendable (Base.Element, Base.Element) async -> Base.Element

  @inlinable
  init(_ base: Base, transform: @Sendable @escaping (Base.Element, Base.Element) async -> Base.Element) {
    self.base = base
    self.transform = transform
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension AsyncInclusiveReductionsSequence: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncInclusiveReductionsSequence` instance.
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    internal var iterator: Base.AsyncIterator

    @usableFromInline
    internal var element: Base.Element?

    @usableFromInline
    internal let transform: @Sendable (Base.Element, Base.Element) async -> Base.Element

    @inlinable
    init(
      _ iterator: Base.AsyncIterator,
      transform: @Sendable @escaping (Base.Element, Base.Element) async -> Base.Element
    ) {
      self.iterator = iterator
      self.transform = transform
    }

    @inlinable
    public mutating func next() async rethrows -> Base.Element? {
      guard let previous = element else {
        element = try await iterator.next()
        return element
      }
      guard let next = try await iterator.next() else { return nil }
      element = await transform(previous, next)
      return element
    }
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator(), transform: transform)
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension AsyncInclusiveReductionsSequence: Sendable where Base: Sendable {}

@available(*, unavailable)
extension AsyncInclusiveReductionsSequence.Iterator: Sendable {}

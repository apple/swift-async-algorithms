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
extension AsyncSequence where Element: AsyncSequence {
  /// Concatenate an `AsyncSequence` of `AsyncSequence` elements
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func joined() -> AsyncJoinedSequence<Self> {
    return AsyncJoinedSequence(self)
  }
}

/// An `AsyncSequence` that concatenates`AsyncSequence` elements
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncJoinedSequence<Base: AsyncSequence>: AsyncSequence where Base.Element: AsyncSequence {
  public typealias Element = Base.Element.Element
  public typealias AsyncIterator = Iterator

  /// The iterator for an `AsyncJoinedSequence` instance.
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    enum State {
      case initial(Base.AsyncIterator)
      case sequence(Base.AsyncIterator, Base.Element.AsyncIterator)
      case terminal
    }

    @usableFromInline
    var state: State

    @inlinable
    init(_ iterator: Base.AsyncIterator) {
      state = .initial(iterator)
    }

    @inlinable
    public mutating func next() async rethrows -> Base.Element.Element? {
      do {
        switch state {
        case .terminal:
          return nil
        case .initial(var outerIterator):
          guard let innerSequence = try await outerIterator.next() else {
            state = .terminal
            return nil
          }
          let innerIterator = innerSequence.makeAsyncIterator()
          state = .sequence(outerIterator, innerIterator)
          return try await next()
        case .sequence(var outerIterator, var innerIterator):
          if let item = try await innerIterator.next() {
            state = .sequence(outerIterator, innerIterator)
            return item
          }

          guard let nextInner = try await outerIterator.next() else {
            state = .terminal
            return nil
          }

          state = .sequence(outerIterator, nextInner.makeAsyncIterator())
          return try await next()
        }
      } catch {
        state = .terminal
        throw error
      }
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
    return Iterator(base.makeAsyncIterator())
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncJoinedSequence: Sendable
where Base: Sendable, Base.Element: Sendable, Base.Element.Element: Sendable {}

@available(*, unavailable)
extension AsyncJoinedSequence.Iterator: Sendable {}

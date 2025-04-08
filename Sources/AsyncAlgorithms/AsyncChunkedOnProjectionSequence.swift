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
  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type on the uniqueness of a given subject.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func chunked<Subject: Equatable, Collected: RangeReplaceableCollection>(
    into: Collected.Type,
    on projection: @escaping @Sendable (Element) -> Subject
  ) -> AsyncChunkedOnProjectionSequence<Self, Subject, Collected> {
    AsyncChunkedOnProjectionSequence(self, projection: projection)
  }

  /// Creates an asynchronous sequence that creates chunks on the uniqueness of a given subject.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func chunked<Subject: Equatable>(
    on projection: @escaping @Sendable (Element) -> Subject
  ) -> AsyncChunkedOnProjectionSequence<Self, Subject, [Element]> {
    chunked(into: [Element].self, on: projection)
  }
}

/// An `AsyncSequence` that chunks on a subject when it differs from the last element.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncChunkedOnProjectionSequence<
  Base: AsyncSequence,
  Subject: Equatable,
  Collected: RangeReplaceableCollection
>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = (Subject, Collected)

  /// The iterator for a `AsyncChunkedOnProjectionSequence` instance.
  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let projection: @Sendable (Base.Element) -> Subject

    @usableFromInline
    init(base: Base.AsyncIterator, projection: @escaping @Sendable (Base.Element) -> Subject) {
      self.base = base
      self.projection = projection
    }

    @usableFromInline
    var hangingNext: (Subject, Base.Element)?

    @inlinable
    public mutating func next() async rethrows -> (Subject, Collected)? {
      var firstOpt = hangingNext
      if firstOpt == nil {
        let nextOpt = try await base.next()
        if let next = nextOpt {
          firstOpt = (projection(next), next)
        }
      } else {
        hangingNext = nil
      }

      guard let first = firstOpt else {
        return nil
      }

      var result: Collected = .init()
      result.append(first.1)

      while let next = try await base.next() {
        let subj = projection(next)
        guard subj == first.0 else {
          hangingNext = (subj, next)
          break
        }
        result.append(next)
      }
      return (first.0, result)
    }
  }

  @usableFromInline
  let base: Base

  @usableFromInline
  let projection: @Sendable (Base.Element) -> Subject

  @usableFromInline
  init(_ base: Base, projection: @escaping @Sendable (Base.Element) -> Subject) {
    self.base = base
    self.projection = projection
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), projection: projection)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncChunkedOnProjectionSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncChunkedOnProjectionSequence.Iterator: Sendable {}

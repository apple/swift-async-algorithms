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

/// Returns a new asynchronous sequence that iterates over the three given asynchronous sequences, one
/// followed by the other.
///
/// - Parameters:
///   - s1: The first asynchronous sequence.
///   - s2: The second asynchronous sequence.
///   - s3: The third asynchronous sequence.
/// - Returns: An asynchronous sequence that iterates first over the elements of `s1`, and
///   then over the elements of `s2`, and then over the elements of `s3`
@available(AsyncAlgorithms 1.0, *)
@inlinable
public func chain<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(
  _ s1: Base1,
  _ s2: Base2,
  _ s3: Base3
) -> AsyncChain3Sequence<Base1, Base2, Base3> {
  AsyncChain3Sequence(s1, s2, s3)
}

/// A concatenation of three asynchronous sequences with the same element type.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncChain3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>
where Base1.Element == Base2.Element, Base1.Element == Base3.Element {
  @usableFromInline
  let base1: Base1

  @usableFromInline
  let base2: Base2

  @usableFromInline
  let base3: Base3

  @usableFromInline
  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncChain3Sequence: AsyncSequence {
  public typealias Element = Base1.Element

  /// The iterator for a `AsyncChain3Sequence` instance.
  @available(AsyncAlgorithms 1.0, *)
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var base1: Base1.AsyncIterator?

    @usableFromInline
    var base2: Base2.AsyncIterator?

    @usableFromInline
    var base3: Base3.AsyncIterator?

    @usableFromInline
    init(_ base1: Base1.AsyncIterator, _ base2: Base2.AsyncIterator, _ base3: Base3.AsyncIterator) {
      self.base1 = base1
      self.base2 = base2
      self.base3 = base3
    }

    @inlinable
    public mutating func next() async rethrows -> Element? {
      do {
        if let value = try await base1?.next() {
          return value
        } else {
          base1 = nil
        }
        if let value = try await base2?.next() {
          return value
        } else {
          base2 = nil
        }
        return try await base3?.next()
      } catch {
        base1 = nil
        base2 = nil
        base3 = nil
        throw error
      }
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator(), base3.makeAsyncIterator())
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncChain3Sequence: Sendable where Base1: Sendable, Base2: Sendable, Base3: Sendable {}

@available(*, unavailable)
extension AsyncChain3Sequence.Iterator: Sendable {}

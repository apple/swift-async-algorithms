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

/// Returns a new asynchronous sequence that iterates over the two given asynchronous sequences, one
/// followed by the other.
///
/// - Parameters:
///   - s1: The first asynchronous sequence.
///   - s2: The second asynchronous sequence.
/// - Returns: An asynchronous sequence that iterates first over the elements of `s1`, and
///   then over the elements of `s2`.
@available(AsyncAlgorithms 1.0, *)
@inlinable
public func chain<Base1: AsyncSequence, Base2: AsyncSequence>(
  _ s1: Base1,
  _ s2: Base2
) -> AsyncChain2Sequence<Base1, Base2> where Base1.Element == Base2.Element {
  AsyncChain2Sequence(s1, s2)
}

/// A concatenation of two asynchronous sequences with the same element type.
@available(AsyncAlgorithms 1.0, *)
@frozen
public struct AsyncChain2Sequence<Base1: AsyncSequence, Base2: AsyncSequence> where Base1.Element == Base2.Element {
  @usableFromInline
  let base1: Base1

  @usableFromInline
  let base2: Base2

  @usableFromInline
  init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncChain2Sequence: AsyncSequence {
  public typealias Element = Base1.Element

  /// The iterator for a `AsyncChain2Sequence` instance.
  @available(AsyncAlgorithms 1.0, *)
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var base1: Base1.AsyncIterator?

    @usableFromInline
    var base2: Base2.AsyncIterator?

    @usableFromInline
    init(_ base1: Base1.AsyncIterator, _ base2: Base2.AsyncIterator) {
      self.base1 = base1
      self.base2 = base2
    }

    @inlinable
    public mutating func next() async rethrows -> Element? {
      do {
        if let value = try await base1?.next() {
          return value
        } else {
          base1 = nil
        }
        return try await base2?.next()
      } catch {
        base1 = nil
        base2 = nil
        throw error
      }
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator())
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncChain2Sequence: Sendable where Base1: Sendable, Base2: Sendable {}

@available(*, unavailable)
extension AsyncChain2Sequence.Iterator: Sendable {}

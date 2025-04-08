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

import DequeModule

/// Creates an asynchronous sequence of elements from two underlying asynchronous sequences
@available(AsyncAlgorithms 1.0, *)
public func merge<Base1: AsyncSequence, Base2: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2
) -> AsyncMerge2Sequence<Base1, Base2>
where
  Base1.Element == Base2.Element,
  Base1: Sendable,
  Base2: Sendable,
  Base1.Element: Sendable
{
  return AsyncMerge2Sequence(base1, base2)
}

/// An `AsyncSequence` that takes two upstream `AsyncSequence`s and combines their elements.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncMerge2Sequence<
  Base1: AsyncSequence,
  Base2: AsyncSequence
>: Sendable
where
  Base1.Element == Base2.Element,
  Base1: Sendable,
  Base2: Sendable,
  Base1.Element: Sendable
{
  public typealias Element = Base1.Element

  private let base1: Base1
  private let base2: Base2

  /// Initializes a new ``AsyncMerge2Sequence``.
  ///
  /// - Parameters:
  ///     - base1: The first upstream ``Swift/AsyncSequence``.
  ///     - base2: The second upstream ``Swift/AsyncSequence``.
  init(
    _ base1: Base1,
    _ base2: Base2
  ) {
    self.base1 = base1
    self.base2 = base2
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncMerge2Sequence: AsyncSequence {
  @available(AsyncAlgorithms 1.0, *)
  public func makeAsyncIterator() -> Iterator {
    let storage = MergeStorage<Base1, Base2, Base1>(
      base1: base1,
      base2: base2,
      base3: nil
    )
    return Iterator(storage: storage)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncMerge2Sequence {
  @available(AsyncAlgorithms 1.0, *)
  public struct Iterator: AsyncIteratorProtocol {
    /// This class is needed to hook the deinit to observe once all references to the ``AsyncIterator`` are dropped.
    ///
    /// If we get move-only types we should be able to drop this class and use the `deinit` of the ``AsyncIterator`` struct itself.
    final class InternalClass: Sendable {
      private let storage: MergeStorage<Base1, Base2, Base1>

      fileprivate init(storage: MergeStorage<Base1, Base2, Base1>) {
        self.storage = storage
      }

      deinit {
        self.storage.iteratorDeinitialized()
      }

      func next() async rethrows -> Element? {
        try await storage.next()
      }
    }

    let internalClass: InternalClass

    fileprivate init(storage: MergeStorage<Base1, Base2, Base1>) {
      internalClass = InternalClass(storage: storage)
    }

    public mutating func next() async rethrows -> Element? {
      try await internalClass.next()
    }
  }
}

@available(*, unavailable)
extension AsyncMerge2Sequence.Iterator: Sendable {}

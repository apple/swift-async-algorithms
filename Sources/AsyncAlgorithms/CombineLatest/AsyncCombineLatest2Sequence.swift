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

/// Creates an asynchronous sequence that combines the latest values from two `AsyncSequence` types
/// by emitting a tuple of the values. ``combineLatest(_:_:)`` only emits a value whenever any of the base `AsyncSequence`s
/// emit a value (so long as each of the bases have emitted at least one value).
///
/// Finishes:
/// ``combineLatest(_:_:)`` finishes when one of the bases finishes before emitting any value or
/// when all bases finished.
///
/// Throws:
/// ``combineLatest(_:_:)`` throws when one of the bases throws. If one of the bases threw any buffered and not yet consumed
/// values will be dropped.
@available(AsyncAlgorithms 1.0, *)
public func combineLatest<
  Base1: AsyncSequence,
  Base2: AsyncSequence
>(_ base1: Base1, _ base2: Base2) -> AsyncCombineLatest2Sequence<Base1, Base2>
where
  Base1: Sendable,
  Base1.Element: Sendable,
  Base2: Sendable,
  Base2.Element: Sendable
{
  AsyncCombineLatest2Sequence(base1, base2)
}

/// An `AsyncSequence` that combines the latest values produced from two asynchronous sequences into an asynchronous sequence of tuples.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncCombineLatest2Sequence<
  Base1: AsyncSequence,
  Base2: AsyncSequence
>: AsyncSequence, Sendable
where
  Base1: Sendable,
  Base1.Element: Sendable,
  Base2: Sendable,
  Base2.Element: Sendable
{
  public typealias Element = (Base1.Element, Base2.Element)
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2

  init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(storage: .init(self.base1, self.base2, nil))
  }

  public struct Iterator: AsyncIteratorProtocol {
    final class InternalClass {
      private let storage: CombineLatestStorage<Base1, Base2, Base2>

      fileprivate init(storage: CombineLatestStorage<Base1, Base2, Base2>) {
        self.storage = storage
      }

      deinit {
        self.storage.iteratorDeinitialized()
      }

      func next() async rethrows -> Element? {
        guard let element = try await self.storage.next() else {
          return nil
        }

        return (element.0, element.1)
      }
    }

    let internalClass: InternalClass

    fileprivate init(storage: CombineLatestStorage<Base1, Base2, Base2>) {
      self.internalClass = InternalClass(storage: storage)
    }

    public mutating func next() async rethrows -> Element? {
      try await self.internalClass.next()
    }
  }
}

@available(*, unavailable)
extension AsyncCombineLatest2Sequence.Iterator: Sendable {}

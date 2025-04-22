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

/// Creates an asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
@available(AsyncAlgorithms 1.0, *)
public func zip<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2,
  _ base3: Base3
) -> AsyncZip3Sequence<Base1, Base2, Base3> {
  AsyncZip3Sequence(base1, base2, base3)
}

/// An asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncZip3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: AsyncSequence,
  Sendable
where
  Base1: Sendable,
  Base1.Element: Sendable,
  Base2: Sendable,
  Base2.Element: Sendable,
  Base3: Sendable,
  Base3.Element: Sendable
{
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2
  let base3: Base3

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      storage: .init(self.base1, self.base2, self.base3)
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    final class InternalClass {
      private let storage: ZipStorage<Base1, Base2, Base3>

      fileprivate init(storage: ZipStorage<Base1, Base2, Base3>) {
        self.storage = storage
      }

      deinit {
        self.storage.iteratorDeinitialized()
      }

      func next() async rethrows -> Element? {
        guard let element = try await self.storage.next() else {
          return nil
        }

        // This force unwrap is safe since there must be a third element.
        return (element.0, element.1, element.2!)
      }
    }

    let internalClass: InternalClass

    fileprivate init(storage: ZipStorage<Base1, Base2, Base3>) {
      self.internalClass = InternalClass(storage: storage)
    }

    public mutating func next() async rethrows -> Element? {
      try await self.internalClass.next()
    }
  }
}

@available(*, unavailable)
extension AsyncZip3Sequence.Iterator: Sendable {}

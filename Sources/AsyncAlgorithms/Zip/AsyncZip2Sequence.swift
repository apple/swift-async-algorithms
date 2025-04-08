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

/// Creates an asynchronous sequence that concurrently awaits values from two `AsyncSequence` types
/// and emits a tuple of the values.
@available(AsyncAlgorithms 1.0, *)
public func zip<Base1: AsyncSequence, Base2: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2
) -> AsyncZip2Sequence<Base1, Base2> {
  AsyncZip2Sequence(base1, base2)
}

/// An asynchronous sequence that concurrently awaits values from two `AsyncSequence` types
/// and emits a tuple of the values.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncZip2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: AsyncSequence, Sendable
where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable {
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
      private let storage: ZipStorage<Base1, Base2, Base2>

      fileprivate init(storage: ZipStorage<Base1, Base2, Base2>) {
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

    fileprivate init(storage: ZipStorage<Base1, Base2, Base2>) {
      self.internalClass = InternalClass(storage: storage)
    }

    public mutating func next() async rethrows -> Element? {
      try await self.internalClass.next()
    }
  }
}

@available(*, unavailable)
extension AsyncZip2Sequence.Iterator: Sendable {}

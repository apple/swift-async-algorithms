//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// Creates an asynchronous sequence that combines the latest values from many `AsyncSequence` types
/// by emitting a tuple of the values. ``combineLatestMany(_:)`` only emits a value whenever any of the base `AsyncSequence`s
/// emit a value (so long as each of the bases have emitted at least one value).
///
/// Finishes:
/// ``combineLatestMany(_:)`` finishes when one of the bases finishes before emitting any value or
/// when all bases finished.
///
/// Throws:
/// ``combineLatestMany(_:)`` throws when one of the bases throws. If one of the bases threw any buffered and not yet consumed
/// values will be dropped.
@available(AsyncAlgorithms 1.1, *)
public func combineLatestMany<Element: Sendable, Failure: Error>(
    _ bases: [any (AsyncSequence<Element, Failure> & Sendable)]
) -> some AsyncSequence<[Element], Failure> & Sendable {
  AsyncCombineLatestManySequence<Element, Failure>(bases)
}

/// An `AsyncSequence` that combines the latest values produced from many asynchronous sequences into an asynchronous sequence of tuples.
@available(AsyncAlgorithms 1.1, *)
public struct AsyncCombineLatestManySequence<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  public typealias AsyncIterator = Iterator
    
  typealias Base = AsyncSequence<Element, Failure> & Sendable
  let bases: [any Base]

  init(_ bases: [any Base]) {
    self.bases = bases
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      storage: .init(self.bases)
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    final class InternalClass {
      private let storage: CombineLatestManyStorage<Element, Failure>

      fileprivate init(storage: CombineLatestManyStorage<Element, Failure>) {
        self.storage = storage
      }

      deinit {
        self.storage.iteratorDeinitialized()
      }

      func next() async throws(Failure) -> [Element]? {
          fatalError()
//        guard let element = try await self.storage.next() else {
//          return nil
//        }
//
//        // This force unwrap is safe since there must be a third element.
//        return element
      }
    }

    let internalClass: InternalClass

    fileprivate init(storage: CombineLatestManyStorage<Element, Failure>) {
      self.internalClass = InternalClass(storage: storage)
    }

    public mutating func next() async throws(Failure) -> [Element]? {
      try await self.internalClass.next()
    }
  }
}

@available(*, unavailable)
extension AsyncCombineLatestManySequence.Iterator: Sendable {}

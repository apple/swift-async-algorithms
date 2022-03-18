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

/// Creates an asynchronous sequence that combines the latest values from three `AsyncSequence` types
/// by emitting a tuple of the values.
public func combineLatest<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(_ base1: Base1, _ base2: Base2, _ base3: Base3) -> AsyncCombineLatest3Sequence<Base1, Base2, Base3> {
  AsyncCombineLatest3Sequence(base1, base2, base3)
}

/// An `AsyncSequence` that combines the latest values produced from three asynchronous sequences into an asynchronous sequence of tuples.
public struct AsyncCombineLatest3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
  where
    Base1: Sendable, Base2: Sendable, Base3: Sendable,
    Base1.Element: Sendable, Base2.Element: Sendable, Base3.Element: Sendable,
    Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable, Base3.AsyncIterator: Sendable {
  let base1: Base1
  let base2: Base2
  let base3: Base3
  
  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }
}

extension AsyncCombineLatest3Sequence: AsyncSequence {
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)
  
  /// The iterator for a `AsyncCombineLatest3Sequence` instance.
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    var iterator: AsyncCombineLatest2Sequence<AsyncCombineLatest2Sequence<Base1, Base2>, Base3>.Iterator
    
    init(_ base1: Base1.AsyncIterator, _ base2: Base2.AsyncIterator, _ base3: Base3.AsyncIterator) {
      iterator = AsyncCombineLatest2Sequence<AsyncCombineLatest2Sequence<Base1, Base2>, Base3>.Iterator(AsyncCombineLatest2Sequence<Base1, Base2>.Iterator(base1, base2), base3)
    }
    
    public mutating func next() async rethrows -> (Base1.Element, Base2.Element, Base3.Element)? {
      guard let value = try await iterator.next() else {
        return nil
      }
      return (value.0.0, value.0.1, value.1)
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator(), base3.makeAsyncIterator())
  }
}

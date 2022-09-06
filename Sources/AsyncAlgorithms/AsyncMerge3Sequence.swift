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

/// Creates an asynchronous sequence of elements from three underlying asynchronous sequences
public func merge<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2,
  _ base3: Base3
) -> AsyncMerge3Sequence<Base1, Base2, Base3> {
  AsyncMerge3Sequence(base1, base2, base3)
}

/// An asynchronous sequence of elements from three underlying asynchronous sequences
///
/// In a `AsyncMerge3Sequence` instance, the *i*th element is the *i*th element
/// resolved in sequential order out of the two underlying asynchronous sequences.
/// Use the `merge(_:_:_:)` function to create an `AsyncMerge3Sequence`.
public struct AsyncMerge3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: AsyncSequence
where Base1.Element == Base2.Element, Base3.Element == Base2.Element {
  public typealias Element = Base1.Element
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2
  let base3: Base3

  public init(_ base1: Base1, _ base2: Base2,  _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      base1: self.base1,
      base2: self.base2,
      base3: self.base3
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let mergeStateMachine: MergeStateMachine<Element>

    init(base1: Base1, base2: Base2, base3: Base3) {
      self.mergeStateMachine = MergeStateMachine(
        base1,
        base2,
        base3
      )
    }

    public mutating func next() async rethrows -> Element? {
      let mergedElement = await self.mergeStateMachine.next()
      switch mergedElement {
        case .element(let result):
          return try result._rethrowGet()
        case .termination:
          return nil
      }
    }
  }
}

extension AsyncMerge3Sequence: Sendable where Base1: Sendable, Base2: Sendable, Base3: Sendable {}
extension AsyncMerge3Sequence.Iterator: Sendable where Base1: Sendable, Base2: Sendable, Base3: Sendable {}

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

/// Creates an asynchronous sequence of elements from many underlying asynchronous sequences
public func merge<Base: AsyncSequence>(
  _ bases: Base...
) -> AsyncMergeSequence<Base>{
  AsyncMergeSequence(bases)
}

/// An asynchronous sequence of elements from many underlying asynchronous sequences
///
/// In a `AsyncMergeSequence` instance, the *i*th element is the *i*th element
/// resolved in sequential order out of the two underlying asynchronous sequences.
/// Use the `merge(...)` function to create an `AsyncMergeSequence`.
public struct AsyncMergeSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  let bases: [Base]

  public init(_ bases: [Base]) {
    self.bases = bases
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      bases: self.bases
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let mergeStateMachine: MergeStateMachine<Element>

    init(bases: [Base]) {
      self.mergeStateMachine = MergeStateMachine(
        bases
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

extension AsyncMergeSequence: Sendable where Base: Sendable {}
extension AsyncMergeSequence.Iterator: Sendable where Base: Sendable {}

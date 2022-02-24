//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension AsyncSequence {

  @inlinable
  public func chunks<Collected: RangeReplaceableCollection>(ofCount count: Int, collectedInto: Collected.Type) -> AsyncChunksOfCountSequence<Self, [Element]> where Collected.Element == Element {
    AsyncChunksOfCountSequence(self, count: count)
  }

  @inlinable
  public func chunks(ofCount count: Int) -> AsyncChunksOfCountSequence<Self, [Element]> {
    chunks(ofCount: count, collectedInto: [Element].self)
  }

}

public struct AsyncChunksOfCountSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = Collected

  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let count: Int

    @usableFromInline
    init(base: Base.AsyncIterator, count: Int) {
      self.base = base
      self.count = count
    }

    @inlinable
    public mutating func next() async rethrows -> Collected? {
      guard let first = try await base.next() else {
        return nil
      }

      var result: Collected = .init()
      result.append(first)

      while let next = try await base.next() {
        result.append(next)
        if result.count == count {
          break
        }
      }
      return result
    }
  }

  @usableFromInline
  let base : Base

  @usableFromInline
  let count : Int

  @inlinable
  init(_ base: Base, count: Int) {
    precondition(count > 0)
    self.base = base
    self.count = count
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), count: count)
  }
}

extension AsyncChunksOfCountSequence : Sendable where Base : Sendable, Base.Element : Sendable { }
extension AsyncChunksOfCountSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Base.Element : Sendable { }

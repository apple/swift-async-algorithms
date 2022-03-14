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
  public func chunked<Collected: RangeReplaceableCollection>(into: Collected.Type, by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool) -> AsyncChunkedByGroupSequence<Self, Collected> where Collected.Element == Element {
    AsyncChunkedByGroupSequence(self, grouping: belongInSameGroup)
  }

  @inlinable
  public func chunked(by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool) -> AsyncChunkedByGroupSequence<Self, [Element]> {
    chunked(into: [Element].self, by: belongInSameGroup)
  }
}

public struct AsyncChunkedByGroupSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = Collected

  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let grouping: @Sendable (Base.Element, Base.Element) -> Bool

    @usableFromInline
    init(base: Base.AsyncIterator, grouping: @escaping @Sendable (Base.Element, Base.Element) -> Bool) {
      self.base = base
      self.grouping = grouping
    }

    @usableFromInline
    var hangingNext: Base.Element?

    @inlinable
    public mutating func next() async rethrows -> Collected? {
      var firstOpt = hangingNext
      if firstOpt == nil {
        firstOpt = try await base.next()
      } else {
        hangingNext = nil
      }
      
      guard let first = firstOpt else {
        return nil
      }

      var result: Collected = .init()
      result.append(first)

      var prev = first
      while let next = try await base.next() {
        if grouping(prev, next) {
          result.append(next)
          prev = next
        } else {
          hangingNext = next
          break
        }
      }
      return result
    }
  }

  @usableFromInline
  let base : Base

  @usableFromInline
  let grouping : @Sendable (Base.Element, Base.Element) -> Bool

  @inlinable
  init(_ base: Base, grouping: @escaping @Sendable (Base.Element, Base.Element) -> Bool) {
    self.base = base
    self.grouping = grouping
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), grouping: grouping)
  }
}

extension AsyncChunkedByGroupSequence : Sendable where Base : Sendable, Base.Element : Sendable { }
extension AsyncChunkedByGroupSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Base.Element : Sendable { }

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

extension Sequence {
  @inlinable
  public var async: AsyncLazySequence<Self> {
    AsyncLazySequence(self)
  }
}

@frozen
public struct AsyncLazySequence<Base: Sequence>: AsyncSequence {
  public typealias Element = Base.Element
  
  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var iterator: Base.Iterator?
    
    @usableFromInline
    init(_ iterator: Base.Iterator) {
      self.iterator = iterator
    }
    
    @inlinable
    public mutating func next() async -> Base.Element? {
      guard !Task.isCancelled, var iterator = iterator else {
        iterator = nil
        return nil
      }
      if let value = iterator.next() {
        self.iterator = iterator
        return value
      } else {
        self.iterator = nil
        return nil
      }
    }
  }
  
  @usableFromInline
  let base: Base
  
  @usableFromInline
  init(_ base: Base) {
    self.base = base
  }
  
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeIterator())
  }
}

extension AsyncLazySequence: Sendable where Base: Sendable { }
extension AsyncLazySequence.Iterator: Sendable where Base.Iterator: Sendable { }

extension AsyncLazySequence: Codable where Base: Codable { }

extension AsyncLazySequence: Equatable where Base: Equatable { }

extension AsyncLazySequence: Hashable where Base: Hashable { }



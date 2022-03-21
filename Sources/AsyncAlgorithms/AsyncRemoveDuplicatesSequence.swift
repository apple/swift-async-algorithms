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

extension AsyncSequence where Element: Equatable {
  /// Creates an asynchronous sequence that omits repeated elements.
  public func removeDuplicates() -> AsyncRemoveDuplicatesSequence<Self> {
    AsyncRemoveDuplicatesSequence(self) { lhs, rhs in
      lhs == rhs
    }
  }
}

extension AsyncSequence {
  /// Creates an asynchronous sequence that omits repeated elements by testing them with a predicate.
  public func removeDuplicates(by predicate: @escaping @Sendable (Element, Element) async -> Bool) -> AsyncRemoveDuplicatesSequence<Self> {
    return AsyncRemoveDuplicatesSequence(self, predicate: predicate)
  }
  
  /// Creates an asynchronous sequence that omits repeated elements by testing them with an error-throwing predicate.
  public func removeDuplicates(by predicate: @escaping @Sendable (Element, Element) async throws -> Bool) -> AsyncThrowingRemoveDuplicatesSequence<Self> {
    return AsyncThrowingRemoveDuplicatesSequence(self, predicate: predicate)
  }
}

/// An asynchronous sequence that omits repeated elements by testing them with a predicate.
public struct AsyncRemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncRemoveDuplicatesSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var iterator: Base.AsyncIterator

    @usableFromInline
    let predicate: @Sendable (Element, Element) async -> Bool

    @usableFromInline
    var last: Element?

    @inlinable
    init(iterator: Base.AsyncIterator, predicate: @escaping @Sendable (Element, Element) async -> Bool) {
      self.iterator = iterator
      self.predicate = predicate
    }

    @inlinable
    public mutating func next() async rethrows -> Element? {
      guard let last = last else {
        last = try await iterator.next()
        return last
      }
      while let element = try await iterator.next() {
        if await !predicate(last, element) {
          self.last = element
          return element
        }
      }
      return nil
    }
  }

  @usableFromInline
  let base: Base

  @usableFromInline
  let predicate: @Sendable (Element, Element) async -> Bool
  
  init(_ base: Base, predicate: @escaping @Sendable (Element, Element) async -> Bool) {
    self.base = base
    self.predicate = predicate
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(iterator: base.makeAsyncIterator(), predicate: predicate)
  }
}

extension AsyncRemoveDuplicatesSequence: Sendable where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }
extension AsyncRemoveDuplicatesSequence.Iterator: Sendable where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }


/// An asynchronous sequence that omits repeated elements by testing them with an error-throwing predicate.
public struct AsyncThrowingRemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element
  
  /// The iterator for an `AsyncThrowingRemoveDuplicatesSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var iterator: Base.AsyncIterator

    @usableFromInline
    let predicate: @Sendable (Element, Element) async throws -> Bool

    @usableFromInline
    var last: Element?

    @inlinable
    init(iterator: Base.AsyncIterator, predicate: @escaping @Sendable (Element, Element) async throws -> Bool) {
      self.iterator = iterator
      self.predicate = predicate
    }

    @inlinable
    public mutating func next() async throws -> Element? {
      guard let last = last else {
        last = try await iterator.next()
        return last
      }
      while let element = try await iterator.next() {
        if try await !predicate(last, element) {
          self.last = element
          return element
        }
      }
      return nil
    }
  }

  @usableFromInline
  let base: Base

  @usableFromInline
  let predicate: @Sendable (Element, Element) async throws -> Bool
  
  init(_ base: Base, predicate: @escaping @Sendable (Element, Element) async throws -> Bool) {
    self.base = base
    self.predicate = predicate
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(iterator: base.makeAsyncIterator(), predicate: predicate)
  }
}

extension AsyncThrowingRemoveDuplicatesSequence: Sendable where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }
extension AsyncThrowingRemoveDuplicatesSequence.Iterator: Sendable where Base: Sendable, Base.Element: Sendable, Base.AsyncIterator: Sendable { }

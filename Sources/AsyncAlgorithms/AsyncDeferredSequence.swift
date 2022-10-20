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

@inlinable
public func deferred<Base: AsyncSequence>(_ createSequence: @escaping @Sendable () async -> Base) -> AsyncDeferredSequence<Base> {
  AsyncDeferredSequence(createSequence)
}

@inlinable
public func deferred<Base: AsyncSequence>(_ createSequence: @autoclosure @escaping @Sendable () -> Base) -> AsyncDeferredSequence<Base> {
  AsyncDeferredSequence(createSequence)
}

public struct AsyncDeferredSequence<Base: AsyncSequence> {
  
  @usableFromInline
  let createSequence: @Sendable () async -> Base
  
  @usableFromInline
  init(_ createSequence: @escaping @Sendable () async -> Base) {
    self.createSequence = createSequence
  }
}

extension AsyncDeferredSequence: AsyncSequence {
  
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol {
    
    @usableFromInline
    enum State {
      case pending(@Sendable () async -> Base)
      case active(Base.AsyncIterator)
    }
    
    @usableFromInline
    var state: State
    
    @usableFromInline
    init(_ createSequence: @escaping @Sendable () async -> Base) {
      self.state = .pending(createSequence)
    }
    
    @inlinable
    public mutating func next() async rethrows -> Element? {
      switch state {
      case .pending(let generator):
        state = .active(await generator().makeAsyncIterator())
        return try await next()
      case .active(var base):
        if let value = try await base.next() {
          state = .active(base)
          return value
        }
        else {
          return nil
        }
      }
    }
  }
  
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(createSequence)
  }
}

extension AsyncDeferredSequence: Sendable { }

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

/// Creates a ``AsyncDeferredSequence`` that uses the supplied closure to create a new `AsyncSequence`.
/// The closure is executed for each iterator on the first call to `next`.
/// This has the effect of postponing the initialization of an arbitrary `AsyncSequence` until the point of first demand.
@inlinable
public func deferred<Base>(
  _ createSequence: @escaping @Sendable () async -> Base
) -> AsyncDeferredSequence<Base> where Base: AsyncSequence, Base: Sendable {
  AsyncDeferredSequence(createSequence)
}

/// Creates a ``AsyncDeferredSequence`` that uses the supplied closure to create a new `AsyncSequence`.
/// The closure is executed for each iterator on the first call to `next`.
/// This has the effect of postponing the initialization of an arbitrary `AsyncSequence` until the point of first demand.
@inlinable
public func deferred<Base: AsyncSequence & Sendable>(
  _ createSequence: @autoclosure @escaping @Sendable () -> Base
) -> AsyncDeferredSequence<Base> where Base: AsyncSequence, Base: Sendable {
  AsyncDeferredSequence(createSequence)
}

@frozen
public struct AsyncDeferredSequence<Base> where Base: AsyncSequence, Base: Sendable {
  
  @usableFromInline
  let createSequence: @Sendable () async -> Base
  
  @inlinable
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
      case terminal
    }
    
    @usableFromInline
    var state: State
    
    @inlinable
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
        do {
          if let value = try await base.next() {
            state = .active(base)
            return value
          }
          else {
            state = .terminal
            return nil
          }
        }
        catch let error {
          state = .terminal
          throw error
        }
      case .terminal:
        return nil
      }
    }
  }
  
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(createSequence)
  }
}

extension AsyncDeferredSequence: Sendable { }

@available(*, unavailable)
extension AsyncDeferredSequence.Iterator: Sendable { }

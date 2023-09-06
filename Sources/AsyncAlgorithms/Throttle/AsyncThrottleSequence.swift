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
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func throttle<C: Clock, Reduced>(for interval: C.Instant.Duration, clock: C, reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced) -> AsyncThrottleSequence<Self, C, Reduced> where Self: Sendable {
    AsyncThrottleSequence(self, interval: interval, clock: clock, reducing: reducing)
  }
  
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func throttle<Reduced>(for interval: Duration, reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced) -> AsyncThrottleSequence<Self, ContinuousClock, Reduced> where Self: Sendable {
    throttle(for: interval, clock: .continuous, reducing: reducing)
  }
  
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func throttle<C: Clock>(for interval: C.Instant.Duration, clock: C, latest: Bool = true) -> AsyncThrottleSequence<Self, C, Element> where Self: Sendable {
    throttle(for: interval, clock: clock) { previous, element in
      if latest {
        return element
      } else {
        return previous ?? element
      }
    }
  }
  
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func throttle(for interval: Duration, latest: Bool = true) -> AsyncThrottleSequence<Self, ContinuousClock, Element> where Self: Sendable {
    throttle(for: interval, clock: .continuous, latest: latest)
  }
}

/// A rate-limited `AsyncSequence` by emitting values at most every specified interval.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AsyncThrottleSequence<Base: AsyncSequence & Sendable, C: Clock, Reduced> {
  let base: Base
  let interval: C.Instant.Duration
  let clock: C
  let reducing: @Sendable (Reduced?, Base.Element) async -> Reduced
  
  init(_ base: Base, interval: C.Instant.Duration, clock: C, reducing: @Sendable @escaping (Reduced?, Base.Element) async -> Reduced) {
    self.base = base
    self.interval = interval
    self.clock = clock
    self.reducing = reducing
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncThrottleSequence: AsyncSequence {
  public typealias Element = Reduced

  public func makeAsyncIterator() -> Iterator {
      let storage = ThrottleStorage(
        base,
        interval: interval,
        clock: clock, 
        reducing: reducing
      )
      return Iterator(storage: storage)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncThrottleSequence {
  public struct Iterator: AsyncIteratorProtocol {
    final class InternalClass: Sendable {
      private let storage: ThrottleStorage<Base, C, Reduced>
      
      fileprivate init(storage: ThrottleStorage<Base, C, Reduced>) {
        self.storage = storage
      }
      
      deinit {
        self.storage.iteratorDeinitialized()
      }
      
      func next() async rethrows -> Element? {
        try await self.storage.next()
      }
    }
    
    let internalClass: InternalClass
    
    fileprivate init(storage: ThrottleStorage<Base, C, Reduced>) {
      self.internalClass = InternalClass(storage: storage)
    }
    
    public mutating func next() async rethrows -> Element? {
      try await self.internalClass.next()
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncThrottleSequence: Sendable where Base: Sendable, Element: Sendable { }

@available(*, unavailable)
extension AsyncThrottleSequence.Iterator: Sendable { }

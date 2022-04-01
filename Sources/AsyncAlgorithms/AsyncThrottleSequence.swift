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
  @available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
  public func throttle<C: Clock, Reduced>(for interval: C.Instant.Duration, clock: C, reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced) -> AsyncThrottleSequence<Self, C, Reduced> {
    AsyncThrottleSequence(self, interval: interval, clock: clock, reducing: reducing)
  }
  
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
  public func throttle<Reduced>(for interval: Duration, reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced) -> AsyncThrottleSequence<Self, ContinuousClock, Reduced> {
    throttle(for: interval, clock: .continuous, reducing: reducing)
  }
  
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
  public func throttle<C: Clock>(for interval: C.Instant.Duration, clock: C, latest: Bool = true) -> AsyncThrottleSequence<Self, C, Element> {
    throttle(for: interval, clock: clock) { previous, element in
      if latest {
        return element
      } else {
        return previous ?? element
      }
    }
  }
  
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
  public func throttle(for interval: Duration, latest: Bool = true) -> AsyncThrottleSequence<Self, ContinuousClock, Element> {
    throttle(for: interval, clock: .continuous, latest: latest)
  }
}

/// A rate-limited `AsyncSequence` by emitting values at most every specified interval.
@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
public struct AsyncThrottleSequence<Base: AsyncSequence, C: Clock, Reduced> {
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

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension AsyncThrottleSequence: AsyncSequence {
  public typealias Element = Reduced
  
  /// The iterator for an `AsyncThrottleSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
    var last: C.Instant?
    let interval: C.Instant.Duration
    let clock: C
    let reducing: @Sendable (Reduced?, Base.Element) async -> Reduced
    
    init(_ base: Base.AsyncIterator, interval: C.Instant.Duration, clock: C, reducing: @Sendable @escaping (Reduced?, Base.Element) async -> Reduced) {
      self.base = base
      self.interval = interval
      self.clock = clock
      self.reducing = reducing
    }
    
    public mutating func next() async rethrows -> Reduced? {
      var reduced: Reduced?
      let start = last ?? clock.now
      repeat {
        guard let element = try await base.next() else {
          return nil
        }
        let reduction = await reducing(reduced, element)
        let now = clock.now
        if start.duration(to: now) >= interval || last == nil {
          last = now
          return reduction
        } else {
          reduced = reduction
        }
      } while true
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator(), interval: interval, clock: clock, reducing: reducing)
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension AsyncThrottleSequence: Sendable where Base: Sendable, Element: Sendable { }

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension AsyncThrottleSequence.Iterator: Sendable where Base.AsyncIterator: Sendable { }

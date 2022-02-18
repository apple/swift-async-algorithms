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
  public func throttle<C: Clock, Reduced>(for interval: C.Instant.Duration, clock: C, reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced) -> AsyncThrottleSequence<Self, C, Reduced> {
    AsyncThrottleSequence(self, interval: interval, clock: clock, reducing: reducing)
  }
  
  /*
  public func throttle<Reduced>(for interval: Duration, reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced) -> AsyncThrottleSequence<Self, ContinuousClock, Reduced> {
    throttle(for: interval, clock: .continuous, reducing: reducing)
  }
  */
  
  public func throttle<C: Clock>(for interval: C.Instant.Duration, clock: C, latest: Bool = true) -> AsyncThrottleSequence<Self, C, Element> {
    throttle(for: interval, clock: clock) { previous, element in
      if latest {
        return element
      } else {
        return previous ?? element
      }
    }
  }
  
  /*
  public func throttle(for interval: Duration, latest: Bool = true) -> AsyncThrottleSequence<Self, ContinuousClock, Element> {
    throttle(for: interval, clock: .continuous, latest: latest)
  }
   */
}

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

extension AsyncThrottleSequence: AsyncSequence {
  public typealias Element = Reduced
  
  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
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
      let start = clock.now
      repeat {
        guard let element = try await base.next() else {
          return nil
        }
        let reduction = await reducing(reduced, element)
        if start.duration(to: clock.now) >= interval {
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

extension AsyncThrottleSequence: Sendable where Base: Sendable, Element: Sendable { }
extension AsyncThrottleSequence.Iterator: Sendable where Base.AsyncIterator: Sendable { }

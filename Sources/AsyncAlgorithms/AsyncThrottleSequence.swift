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

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequence {
  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func _throttle<C: Clock, Reduced>(
    for interval: C.Instant.Duration,
    clock: C,
    reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced
  ) -> _AsyncThrottleSequence<Self, C, Reduced> {
    _AsyncThrottleSequence(self, interval: interval, clock: clock, reducing: reducing)
  }

  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func _throttle<Reduced>(
    for interval: Duration,
    reducing: @Sendable @escaping (Reduced?, Element) async -> Reduced
  ) -> _AsyncThrottleSequence<Self, ContinuousClock, Reduced> {
    _throttle(for: interval, clock: .continuous, reducing: reducing)
  }

  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func _throttle<C: Clock>(
    for interval: C.Instant.Duration,
    clock: C,
    latest: Bool = true
  ) -> _AsyncThrottleSequence<Self, C, Element> {
    _throttle(for: interval, clock: clock) { previous, element in
      guard latest else {
        return previous ?? element
      }
      return element
    }
  }

  /// Create a rate-limited `AsyncSequence` by emitting values at most every specified interval.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func _throttle(
    for interval: Duration,
    latest: Bool = true
  ) -> _AsyncThrottleSequence<Self, ContinuousClock, Element> {
    _throttle(for: interval, clock: .continuous, latest: latest)
  }
}

/// A rate-limited `AsyncSequence` by emitting values at most every specified interval.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct _AsyncThrottleSequence<Base: AsyncSequence, C: Clock, Reduced> {
  let base: Base
  let interval: C.Instant.Duration
  let clock: C
  let reducing: @Sendable (Reduced?, Base.Element) async -> Reduced

  init(
    _ base: Base,
    interval: C.Instant.Duration,
    clock: C,
    reducing: @Sendable @escaping (Reduced?, Base.Element) async -> Reduced
  ) {
    self.base = base
    self.interval = interval
    self.clock = clock
    self.reducing = reducing
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension _AsyncThrottleSequence: AsyncSequence {
  public typealias Element = Reduced

  /// The iterator for an `AsyncThrottleSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
    var last: C.Instant?
    let interval: C.Instant.Duration
    let clock: C
    let reducing: @Sendable (Reduced?, Base.Element) async -> Reduced

    init(
      _ base: Base.AsyncIterator,
      interval: C.Instant.Duration,
      clock: C,
      reducing: @Sendable @escaping (Reduced?, Base.Element) async -> Reduced
    ) {
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
          if reduced != nil, let last {
            // ensure the rate of elements never exceeds the given interval
            let amount = interval - last.duration(to: clock.now)
            if amount > .zero {
              try? await clock.sleep(until: clock.now.advanced(by: amount), tolerance: nil)
            }
          }
          // the last value is unable to have any subsequent
          // values so always return the last reduction
          return reduced
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension _AsyncThrottleSequence: Sendable where Base: Sendable, Element: Sendable {}

@available(*, unavailable)
extension _AsyncThrottleSequence.Iterator: Sendable {}

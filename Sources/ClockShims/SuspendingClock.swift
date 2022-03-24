//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Swift
#if canImport(Darwin)
@_implementationOnly import Darwin
#elseif canImport(Glibc)
@_implementationOnly import Glibc
#else
#error("Unsupported platform")
#endif

/// A clock that measures time that always increments but stops incrementing 
/// while the system is asleep. 
///
/// `SuspendingClock` can be considered as a system awake time clock. The frame 
/// of reference of the `Instant` may be bound machine boot or some other 
/// locally defined reference point. This means that the instants are
/// only comparable on the same machine in the same booted session.
///
/// This clock is suitable for high resolution measurements of execution.
@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
public struct SuspendingClock {
  public struct Instant: Codable, Sendable {
    internal var _value: Duration

    internal init(_value: Duration) {
      self._value = _value
    }
  }

  public init() { }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Clock where Self == SuspendingClock {
  /// A clock that measures time that always increments but stops incrementing 
  /// while the system is asleep. 
  ///
  ///       try await Task.sleep(until: .now + .seconds(3), clock: .suspending)
  ///
  public static var suspending: SuspendingClock { return SuspendingClock() }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension SuspendingClock: Clock {
  /// The current instant accounting for machine suspension.
  public var now: SuspendingClock.Instant {
    SuspendingClock.now
  }

  /// The current instant accounting for machine suspension.
  public static var now: SuspendingClock.Instant {
    var ts = timespec()
#if canImport(Darwin)
    clock_gettime(CLOCK_UPTIME_RAW, &ts)
#elseif canImport(Glibc)
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
#endif
    return SuspendingClock.Instant(_value:
        .seconds(ts.tv_sec) + .nanoseconds(ts.tv_nsec))
  }

  /// The minimum non-zero resolution between any two calls to `now`.
  public var minimumResolution: Duration {
    var ts = timespec()
#if canImport(Darwin)
    clock_getres(CLOCK_UPTIME_RAW, &ts)
#elseif canImport(Glibc)
    clock_getres(CLOCK_MONOTONIC, &ts)
#endif
    return .seconds(ts.tv_sec) + .nanoseconds(ts.tv_nsec)
  }

  /// Suspend task execution until a given deadline within a tolerance.
  /// If no tolerance is specified then the system may adjust the deadline
  /// to coalesce CPU wake-ups to more efficiently process the wake-ups in
  /// a more power efficient manner.
  ///
  /// If the task is canceled before the time ends, this function throws 
  /// `CancellationError`.
  ///
  /// This function doesn't block the underlying thread.
  public func sleep(
    until deadline: Instant, tolerance: Duration? = nil
  ) async throws {
    let duration = deadline - .now
    let (seconds, attoseconds) = duration.components
    let nanoseconds = attoseconds / 1_000_000_000 + seconds * 1_000_000_000
    if nanoseconds > 0 {
      try await Task.sleep(nanoseconds: UInt64(nanoseconds))
    }
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension SuspendingClock.Instant: InstantProtocol {
  public static var now: SuspendingClock.Instant { SuspendingClock().now }

  public func advanced(by duration: Duration) -> SuspendingClock.Instant {
    SuspendingClock.Instant(_value: _value + duration)
  }

  public func duration(to other: SuspendingClock.Instant) -> Duration {
    other._value - _value
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(_value)
  }

  public static func == (
    _ lhs: SuspendingClock.Instant, _ rhs: SuspendingClock.Instant
  ) -> Bool {
    return lhs._value == rhs._value
  }

  public static func < (
    _ lhs: SuspendingClock.Instant, _ rhs: SuspendingClock.Instant
  ) -> Bool {
    return lhs._value < rhs._value
  }

  public static func + (
    _ lhs: SuspendingClock.Instant, _ rhs: Duration
  ) -> SuspendingClock.Instant {
    lhs.advanced(by: rhs)
  }

  public static func += (
    _ lhs: inout SuspendingClock.Instant, _ rhs: Duration
  ) {
    lhs = lhs.advanced(by: rhs)
  }

  public static func - (
    _ lhs: SuspendingClock.Instant, _ rhs: Duration
  ) -> SuspendingClock.Instant {
    lhs.advanced(by: .zero - rhs)
  }

  public static func -= (
    _ lhs: inout SuspendingClock.Instant, _ rhs: Duration
  ) {
    lhs = lhs.advanced(by: .zero - rhs)
  }

  public static func - (
    _ lhs: SuspendingClock.Instant, _ rhs: SuspendingClock.Instant
  ) -> Duration {
    rhs.duration(to: lhs)
  }
}


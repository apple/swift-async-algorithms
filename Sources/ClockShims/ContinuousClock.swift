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

/// A clock that measures time that always increments but does not stop 
/// incrementing while the system is asleep. 
///
/// `ContinuousClock` can be considered as a stopwatch style time. The frame of
/// reference of the `Instant` may be bound to process launch, machine boot or
/// some other locally defined reference point. This means that the instants are
/// only comparable locally during the execution of a program.
///
/// This clock is suitable for high resolution measurements of execution.
public struct ContinuousClock {
  /// A continuous point in time used for `ContinuousClock`.
  public struct Instant: Codable, Sendable {
    internal var _value: Duration

    internal init(_value: Duration) {
      self._value = _value
    }
  }

  public init() { }
}

extension Clock where Self == ContinuousClock {
  /// A clock that measures time that always increments but does not stop 
  /// incrementing while the system is asleep. 
  ///
  ///       try await Task.sleep(until: .now + .seconds(3), clock: .continuous)
  ///
  public static var continuous: ContinuousClock { return ContinuousClock() }
}

extension ContinuousClock: Clock {
  /// The current continuous instant.
  public var now: ContinuousClock.Instant {
    ContinuousClock.now
  }

  /// The minimum non-zero resolution between any two calls to `now`.
  public var minimumResolution: Duration {
    var ts = timespec()
#if canImport(Darwin)
    clock_getres(CLOCK_MONOTONIC, &ts)
#elseif canImport(Glibc)
    clock_getres(CLOCK_BOOTTIME, &ts)
#endif
    return .seconds(ts.tv_sec) + .nanoseconds(ts.tv_nsec)
  }

  /// The current continuous instant.
  public static var now: ContinuousClock.Instant {
    var ts = timespec()
#if canImport(Darwin)
    clock_gettime(CLOCK_MONOTONIC, &ts)
#elseif canImport(Glibc)
    clock_gettime(CLOCK_BOOTTIME, &ts)
#endif
    return ContinuousClock.Instant(_value:
        .seconds(ts.tv_sec) + .nanoseconds(ts.tv_nsec))
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

extension ContinuousClock.Instant: InstantProtocol {
  public static var now: ContinuousClock.Instant { ContinuousClock.now }

  public func advanced(by duration: Duration) -> ContinuousClock.Instant {
    return ContinuousClock.Instant(_value: _value + duration)
  }

  public func duration(to other: ContinuousClock.Instant) -> Duration {
    other._value - _value
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(_value)
  }

  public static func == (
    _ lhs: ContinuousClock.Instant, _ rhs: ContinuousClock.Instant
  ) -> Bool {
    return lhs._value == rhs._value
  }

  public static func < (
    _ lhs: ContinuousClock.Instant, _ rhs: ContinuousClock.Instant
  ) -> Bool {
    return lhs._value < rhs._value
  }

  @_alwaysEmitIntoClient
  @inlinable
  public static func + (
    _ lhs: ContinuousClock.Instant, _ rhs: Duration
  ) -> ContinuousClock.Instant {
    lhs.advanced(by: rhs)
  }

  @_alwaysEmitIntoClient
  @inlinable
  public static func += (
    _ lhs: inout ContinuousClock.Instant, _ rhs: Duration
  ) {
    lhs = lhs.advanced(by: rhs)
  }

  @_alwaysEmitIntoClient
  @inlinable
  public static func - (
    _ lhs: ContinuousClock.Instant, _ rhs: Duration
  ) -> ContinuousClock.Instant {
    lhs.advanced(by: .zero - rhs)
  }

  @_alwaysEmitIntoClient
  @inlinable
  public static func -= (
    _ lhs: inout ContinuousClock.Instant, _ rhs: Duration
  ) {
    lhs = lhs.advanced(by: .zero - rhs)
  }

  @_alwaysEmitIntoClient
  @inlinable
  public static func - (
    _ lhs: ContinuousClock.Instant, _ rhs: ContinuousClock.Instant
  ) -> Duration {
    rhs.duration(to: lhs)
  }
}

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

/// A representation of high precision time.
///
/// `Duration` represents an elapsed time value with high precision in an 
/// integral form. It may be used for measurements of varying clock sources. In 
/// those cases it represents the elapsed time measured by that clock. 
/// Calculations using `Duration` may span from a negative value to a positive 
/// value and have a suitable range to at least cover attosecond scale for both
/// small elapsed durations like sub-second precision to durations that span
/// centuries.
///
/// Typical construction of `Duration` values should be created via the
/// static methods for specific time values. 
///
///      var d: Duration = .seconds(3)
///      d += .milliseconds(33)
///      print(d) // 3.033 seconds
///
/// `Duration` itself does not ferry any additional information other than the 
/// temporal measurement component; specifically leap seconds should be 
/// represented as an additional accessor since that is specific only to certain
/// clock implementations.
@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
@frozen
public struct Duration: Sendable {
  /// The low 64 bits of a 128-bit signed integer value counting attoseconds.
  @usableFromInline
  internal var _low: UInt64

  /// The high 64 bits of a 128-bit signed integer value counting attoseconds.
  @usableFromInline
  internal var _high: Int64

  @inlinable
  internal init(_high: Int64, low: UInt64) {
    self._low = low
    self._high = _high
  }

  internal init(_attoseconds: _Int128) {
    self.init(_high: _attoseconds.high, low: _attoseconds.low)
  }

  /// Construct a `Duration` by adding attoseconds to a seconds value.
  ///
  /// This is useful for when an external decomposed components of a `Duration`
  /// has been stored and needs to be reconstituted. Since the values are added
  /// no precondition is expressed for the attoseconds being limited to 1e18.
  ///
  ///       let d1 = Duration(
  ///         secondsComponent: 3, 
  ///         attosecondsComponent: 123000000000000000)
  ///       print(d1) // 3.123 seconds
  ///
  ///       let d2 = Duration(
  ///         secondsComponent: 3, 
  ///         attosecondsComponent: -123000000000000000)
  ///       print(d2) // 2.877 seconds
  ///
  ///       let d3 = Duration(
  ///         secondsComponent: -3, 
  ///         attosecondsComponent: -123000000000000000)
  ///       print(d3) // -3.123 seconds
  ///
  /// - Parameters:
  ///   - secondsComponent: The seconds component portion of the `Duration` 
  ///                       value.
  ///   - attosecondsComponent: The attosecond component portion of the 
  ///                           `Duration` value.
  public init(secondsComponent: Int64, attosecondsComponent: Int64) {
    self = Duration.seconds(secondsComponent) +
           Duration(_attoseconds: _Int128(attosecondsComponent))
  }

  internal var _attoseconds: _Int128 {
    _Int128(high: _high, low: _low)
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration {
  /// The composite components of the `Duration`.
  ///
  /// This is intended for facilitating conversions to existing time types. The
  /// attoseconds value will not exceed 1e18 or be lower than -1e18.
  
  public var components: (seconds: Int64, attoseconds: Int64) {
    let (seconds, attoseconds) = _attoseconds.dividedBy1e18()
    return (Int64(seconds), Int64(attoseconds))
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration {
  /// Construct a `Duration` given a number of seconds represented as a 
  /// `BinaryInteger`.
  ///
  ///       let d: Duration = .seconds(77)
  ///
  /// - Returns: A `Duration` representing a given number of seconds.
  
  public static func seconds<T: BinaryInteger>(_ seconds: T) -> Duration {
    return Duration(_attoseconds:
      _Int128(seconds).multiplied(by: 1_000_000_000_000_000_000 as UInt64))
  }

  /// Construct a `Duration` given a number of seconds represented as a 
  /// `Double` by converting the value into the closest attosecond scale value.
  ///
  ///       let d: Duration = .seconds(22.93)
  ///
  /// - Returns: A `Duration` representing a given number of seconds.
  
  public static func seconds(_ seconds: Double) -> Duration {
    return Duration(_attoseconds: _Int128(seconds * 1_000_000_000_000_000_000))
  }

  /// Construct a `Duration` given a number of milliseconds represented as a 
  /// `BinaryInteger`.
  ///
  ///       let d: Duration = .milliseconds(645)
  ///
  /// - Returns: A `Duration` representing a given number of milliseconds.
  
  public static func milliseconds<T: BinaryInteger>(
    _ milliseconds: T
  ) -> Duration {
    return Duration(_attoseconds:
      _Int128(milliseconds).multiplied(by: 1_000_000_000_000_000 as UInt64))
  }

  /// Construct a `Duration` given a number of seconds milliseconds as a 
  /// `Double` by converting the value into the closest attosecond scale value.
  ///
  ///       let d: Duration = .milliseconds(88.3)
  ///
  /// - Returns: A `Duration` representing a given number of milliseconds.
  
  public static func milliseconds(_ milliseconds: Double) -> Duration {
    return Duration(_attoseconds:
      _Int128(milliseconds * 1_000_000_000_000_000))
  }

  /// Construct a `Duration` given a number of microseconds represented as a 
  /// `BinaryInteger`.
  ///
  ///       let d: Duration = .microseconds(12)
  ///
  /// - Returns: A `Duration` representing a given number of microseconds.
  
  public static func microseconds<T: BinaryInteger>(
    _ microseconds: T
  ) -> Duration {
    return Duration(_attoseconds:
      _Int128(microseconds).multiplied(by: 1_000_000_000_000 as UInt64))
  }

  /// Construct a `Duration` given a number of seconds microseconds as a 
  /// `Double` by converting the value into the closest attosecond scale value.
  ///
  ///       let d: Duration = .microseconds(382.9)
  ///
  /// - Returns: A `Duration` representing a given number of microseconds.
  
  public static func microseconds(_ microseconds: Double) -> Duration {
    return Duration(_attoseconds:
      _Int128(microseconds * 1_000_000_000_000))
  }

  /// Construct a `Duration` given a number of nanoseconds represented as a 
  /// `BinaryInteger`.
  ///
  ///       let d: Duration = .nanoseconds(1929)
  ///
  /// - Returns: A `Duration` representing a given number of nanoseconds.
  
  public static func nanoseconds<T: BinaryInteger>(
    _ nanoseconds: T
  ) -> Duration {
    return Duration(_attoseconds:
      _Int128(nanoseconds).multiplied(by: 1_000_000_000))
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration: Codable {
  
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let high = try container.decode(Int64.self)
    let low = try container.decode(UInt64.self)
    self.init(_high: high, low: low)
  }

  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(_high)
    try container.encode(_low)
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_attoseconds)
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration: Equatable {
  public static func == (_ lhs: Duration, _ rhs: Duration) -> Bool {
    return lhs._attoseconds == rhs._attoseconds
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration: Comparable {
  public static func < (_ lhs: Duration, _ rhs: Duration) -> Bool {
    return lhs._attoseconds < rhs._attoseconds
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration: AdditiveArithmetic {
  
  public static var zero: Duration { Duration(_attoseconds: 0) }

  
  public static func + (_ lhs: Duration, _ rhs: Duration) -> Duration {
    return Duration(_attoseconds: lhs._attoseconds + rhs._attoseconds)
  }

  
  public static func - (_ lhs: Duration, _ rhs: Duration) -> Duration {
    return Duration(_attoseconds: lhs._attoseconds - rhs._attoseconds)
  }

  
  public static func += (_ lhs: inout Duration, _ rhs: Duration) {
    lhs = lhs + rhs
  }

  
  public static func -= (_ lhs: inout Duration, _ rhs: Duration) {
    lhs = lhs - rhs
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration {
  
  public static func / (_ lhs: Duration, _ rhs: Double) -> Duration {
    return Duration(_attoseconds:
      _Int128(Double(lhs._attoseconds) / rhs))
  }

  
  public static func /= (_ lhs: inout Duration, _ rhs: Double) {
    lhs = lhs / rhs
  }

  
  public static func / <T: BinaryInteger>(
    _ lhs: Duration, _ rhs: T
  ) -> Duration {
    Duration(_attoseconds: lhs._attoseconds / _Int128(rhs))
  }

  
  public static func /= <T: BinaryInteger>(_ lhs: inout Duration, _ rhs: T) {
    lhs = lhs / rhs
  }

  
  public static func / (_ lhs: Duration, _ rhs: Duration) -> Double {
    Double(lhs._attoseconds) / Double(rhs._attoseconds)
  }

  
  public static func * (_ lhs: Duration, _ rhs: Double) -> Duration {
    Duration(_attoseconds: _Int128(Double(lhs._attoseconds) * rhs))
  }

  
  public static func * <T: BinaryInteger>(
    _ lhs: Duration, _ rhs: T
  ) -> Duration {
    Duration(_attoseconds: lhs._attoseconds * _Int128(rhs))
  }

  
  public static func *= <T: BinaryInteger>(_ lhs: inout Duration, _ rhs: T) {
    lhs = lhs * rhs
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration: CustomStringConvertible {
  
  public var description: String {
    return (Double(_attoseconds) / 1e18).description + " seconds"
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension Duration: DurationProtocol { }

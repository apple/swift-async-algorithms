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

/// A 128-bit unsigned integer type.
internal struct _UInt128 {
  internal typealias High = UInt64
  internal typealias Low = UInt64

  /// The low part of the value.
  internal var low: Low

  /// The high part of the value.
  internal var high: High

  /// Creates a new instance from the given tuple of high and low parts.
  ///
  /// - Parameter value: The tuple to use as the source of the new instance's
  ///   high and low parts.
  internal init(_ value: (high: High, low: Low)) {
    self.low = value.low
    self.high = value.high
  }

  internal init(high: High, low: Low) {
    self.low = low
    self.high = high
  }

  internal init() {
    self.init(high: 0, low: 0)
  }

  internal init(bitPattern v: _Int128) {
    self.init(high: High(bitPattern: v.high), low: v.low)
  }

  internal static var zero: Self { Self(high: 0, low: 0) }
  internal static var one: Self { Self(high: 0, low: 1) }
}

extension _UInt128: CustomStringConvertible {
  internal var description: String {
    String(self, radix: 10)
  }
}

extension _UInt128: CustomDebugStringConvertible {
  internal var debugDescription: String {
    description
  }
}

extension _UInt128: Equatable {
  internal static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    return (lhs.high, lhs.low) == (rhs.high, rhs.low)
  }
}

extension _UInt128: Comparable {
  internal static func < (_ lhs: Self, _ rhs: Self) -> Bool {
    (lhs.high, lhs.low) < (rhs.high, rhs.low)
  }
}

extension _UInt128: Hashable {
  internal func hash(into hasher: inout Hasher) {
    hasher.combine(low)
    hasher.combine(high)
  }
}

extension _UInt128 {
  internal var components: (high: High, low: Low) {
    @inline(__always) get { (high, low) }
    @inline(__always) set { (self.high, self.low) = (newValue.high, newValue.low) }
  }
}

extension _UInt128: AdditiveArithmetic {
  internal static func - (_ lhs: Self, _ rhs: Self) -> Self {
    let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in -")
    return result
  }

  internal static func -= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in -=")
    lhs = result
  }

  internal static func + (_ lhs: Self, _ rhs: Self) -> Self {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in +")
    return result
  }

  internal static func += (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in +=")
    lhs = result
  }
}

extension _UInt128: Numeric {
  internal typealias Magnitude = _UInt128

  internal var magnitude: Magnitude {
    return self
  }

  internal init(_ magnitude: Magnitude) {
    self.init(high: High(magnitude.high), low: magnitude.low)
  }

  internal init<T: BinaryInteger>(_ source: T) {
    guard let result = Self(exactly: source) else {
      preconditionFailure("Value is outside the representable range")
    }
    self = result
  }

  internal init?<T: BinaryInteger>(exactly source: T) {
    // Can't represent a negative 'source' if Self is unsigned.
    guard Self.isSigned || source >= 0 else {
      return nil
    }

    // Is 'source' entirely representable in Low?
    if let low = Low(exactly: source.magnitude) {
      self.init(source._isNegative ? (~0, low._twosComplement) : (0, low))
    } else {
      // At this point we know source.bitWidth > High.bitWidth, or else we
      // would've taken the first branch.
      let lowInT = source & T(~0 as Low)
      let highInT = source >> Low.bitWidth

      let low = Low(lowInT)
      guard let high = High(exactly: highInT) else {
        return nil
      }
      self.init(high: high, low: low)
    }
  }

  internal static func * (_ lhs: Self, _ rhs: Self) -> Self {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    precondition(!overflow, "Overflow in *")
    return result
  }

  internal static func *= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    precondition(!overflow, "Overflow in *=")
    lhs = result
  }
}

extension _UInt128 {
  internal struct Words {
    internal var _value: _UInt128

    internal init(_ value: _UInt128) {
      self._value = value
    }
  }
}

extension _UInt128.Words: RandomAccessCollection {
  internal typealias Element = UInt
  internal typealias Index = Int
  internal typealias Indices = Range<Int>
  internal typealias SubSequence = Slice<Self>

  internal var count: Int { 128 / UInt.bitWidth }
  internal var startIndex: Int { 0 }
  internal var endIndex: Int { count }
  internal var indices: Indices { startIndex ..< endIndex }
  internal func index(after i: Int) -> Int { i + 1 }
  internal func index(before i: Int) -> Int { i - 1 }

  internal subscript(position: Int) -> UInt {
    get {
      precondition(position >= 0 && position < endIndex,
        "Word index out of range")
      let shift = position &* UInt.bitWidth
      assert(shift < _UInt128.bitWidth)

      let r = _wideMaskedShiftRight(
        _value.components, UInt64(truncatingIfNeeded: shift))
      return r.low._lowWord
    }
  }
}

extension _UInt128: FixedWidthInteger {
  @_transparent
  internal var _lowWord: UInt {
    low._lowWord
  }

  internal var words: Words {
    Words(self)
  }

  internal static var isSigned: Bool {
    false
  }

  internal static var max: Self {
    self.init(high: High.max, low: Low.max)
  }

  internal static var min: Self {
    self.init(high: High.min, low: Low.min)
  }

  internal static var bitWidth: Int { 128 }

  internal func addingReportingOverflow(
    _ rhs: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideAddReportingOverflow22(self.components, rhs.components)
    return (Self(r), o)
  }

  internal func subtractingReportingOverflow(
    _ rhs: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideSubtractReportingOverflow22(
      self.components, rhs.components)
    return (Self(r), o)
  }

  internal func multipliedReportingOverflow(
    by rhs: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let h1 = self.high.multipliedReportingOverflow(by: rhs.low)
    let h2 = self.low.multipliedReportingOverflow(by: rhs.high)
    let h3 = h1.partialValue.addingReportingOverflow(h2.partialValue)
    let (h, l) = self.low.multipliedFullWidth(by: rhs.low)
    let high = h3.partialValue.addingReportingOverflow(h)
    let overflow = (
      (self.high != 0 && rhs.high != 0)
      || h1.overflow || h2.overflow || h3.overflow || high.overflow)
    return (Self(high: high.partialValue, low: l), overflow)
  }

  /// Returns the product of this value and the given 64-bit value, along with a
  /// Boolean value indicating whether overflow occurred in the operation.
  internal func multipliedReportingOverflow(
    by other: UInt64
  ) -> (partialValue: Self, overflow: Bool) {
    let h1 = self.high.multipliedReportingOverflow(by: other)
    let (h2, l) = self.low.multipliedFullWidth(by: other)
    let high = h1.partialValue.addingReportingOverflow(h2)
    let overflow = h1.overflow || high.overflow
    return (Self(high: high.partialValue, low: l), overflow)
  }

  internal func multiplied(by other: UInt64) -> Self {
    let r = multipliedReportingOverflow(by: other)
    precondition(!r.overflow, "Overflow in multiplication")
    return r.partialValue
  }

  internal func quotientAndRemainder(
    dividingBy other: Self
  ) -> (quotient: Self, remainder: Self) {
    let (q, r) = _wideDivide22(
      self.magnitude.components, by: other.magnitude.components)
    let quotient = Self.Magnitude(q)
    let remainder = Self.Magnitude(r)
    return (quotient, remainder)
  }

  internal func dividedReportingOverflow(
    by other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    if other == Self.zero {
      return (self, true)
    }
    if Self.isSigned && other == -1 && self == .min {
      return (self, true)
    }
    return (quotientAndRemainder(dividingBy: other).quotient, false)
  }

  internal func remainderReportingOverflow(
    dividingBy other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    if other == Self.zero {
      return (self, true)
    }
    if Self.isSigned && other == -1 && self == .min {
      return (0, true)
    }
    return (quotientAndRemainder(dividingBy: other).remainder, false)
  }

  internal func multipliedFullWidth(
    by other: Self
  ) -> (high: Self, low: Magnitude) {
    let isNegative = Self.isSigned && (self._isNegative != other._isNegative)

    func sum(_ x: Low, _ y: Low, _ z: Low) -> (high: Low, low: Low) {
      let (sum1, overflow1) = x.addingReportingOverflow(y)
      let (sum2, overflow2) = sum1.addingReportingOverflow(z)
      let carry: Low = (overflow1 ? 1 : 0) + (overflow2 ? 1 : 0)
      return (carry, sum2)
    }

    let lhs = self.magnitude
    let rhs = other.magnitude

    let a = rhs.low.multipliedFullWidth(by: lhs.low)
    let b = rhs.low.multipliedFullWidth(by: lhs.high)
    let c = rhs.high.multipliedFullWidth(by: lhs.low)
    let d = rhs.high.multipliedFullWidth(by: lhs.high)

    let mid1 = sum(a.high, b.low, c.low)
    let mid2 = sum(b.high, c.high, d.low)

    let low = _UInt128(high: mid1.low, low: a.low)
    let high = _UInt128(
      high: High(mid2.high + d.high),
      low: mid1.high + mid2.low)

    if isNegative {
      let (lowComplement, overflow) = (~low).addingReportingOverflow(.one)
      return (~high + (overflow ? 1 : 0), lowComplement)
    } else {
      return (high, low)
    }
  }

  internal func dividingFullWidth(
    _ dividend: (high: Self, low: Self.Magnitude)
  ) -> (quotient: Self, remainder: Self) {
    let (q, r) = _wideDivide42(
      (dividend.high.components, dividend.low.components),
      by: self.components)
    return (Self(q), Self(r))
  }

  #if false // This triggers an unexpected type checking issue with `~0` in an
            // lldb test
  internal static prefix func ~(x: Self) -> Self {
    Self(high: ~x.high, low: ~x.low)
  }
  #endif

  internal static func &= (_ lhs: inout Self, _ rhs: Self) {
    lhs.low &= rhs.low
    lhs.high &= rhs.high
  }

  internal static func |= (_ lhs: inout Self, _ rhs: Self) {
    lhs.low |= rhs.low
    lhs.high |= rhs.high
  }

  internal static func ^= (_ lhs: inout Self, _ rhs: Self) {
    lhs.low ^= rhs.low
    lhs.high ^= rhs.high
  }

  internal static func <<= (_ lhs: inout Self, _ rhs: Self) {
    if Self.isSigned && rhs._isNegative {
      lhs >>= 0 - rhs
      return
    }

    // Shift is larger than this type's bit width.
    if rhs.high != High.zero || rhs.low >= Self.bitWidth {
      lhs = 0
      return
    }

    lhs &<<= rhs
  }

  internal static func >>= (_ lhs: inout Self, _ rhs: Self) {
    if Self.isSigned && rhs._isNegative {
      lhs <<= 0 - rhs
      return
    }

    // Shift is larger than this type's bit width.
    if rhs.high != High.zero || rhs.low >= Self.bitWidth {
      lhs = lhs._isNegative ? ~0 : 0
      return
    }

    lhs &>>= rhs
  }

  internal static func &<< (lhs: Self, rhs: Self) -> Self {
    Self(_wideMaskedShiftLeft(lhs.components, rhs.low))
  }

  internal static func &>> (lhs: Self, rhs: Self) -> Self {
    Self(_wideMaskedShiftRight(lhs.components, rhs.low))
  }

  internal static func &<<= (lhs: inout Self, rhs: Self) {
    _wideMaskedShiftLeft(&lhs.components, rhs.low)
  }

  internal static func &>>= (lhs: inout Self, rhs: Self) {
    _wideMaskedShiftRight(&lhs.components, rhs.low)
  }

  internal static func / (
    _ lhs: Self, _ rhs: Self
  ) -> Self {
    var lhs = lhs
    lhs /= rhs
    return lhs
  }

  internal static func /= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.dividedReportingOverflow(by: rhs)
    precondition(!overflow, "Overflow in /=")
    lhs = result
  }

  internal static func % (
    _ lhs: Self, _ rhs: Self
  ) -> Self {
    var lhs = lhs
    lhs %= rhs
    return lhs
  }

  internal static func %= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.remainderReportingOverflow(dividingBy: rhs)
    precondition(!overflow, "Overflow in %=")
    lhs = result
  }

  internal init(_truncatingBits bits: UInt) {
    low = Low(_truncatingBits: bits)
    high = High(_truncatingBits: bits >> UInt(Low.bitWidth))
  }

  internal init(integerLiteral x: Int64) {
    self.init(x)
  }

  internal var leadingZeroBitCount: Int {
    (high == High.zero
      ? High.bitWidth + low.leadingZeroBitCount
      : high.leadingZeroBitCount)
  }

  internal var trailingZeroBitCount: Int {
    (low == Low.zero
      ? Low.bitWidth + high.trailingZeroBitCount
      : low.trailingZeroBitCount)
  }

  internal var nonzeroBitCount: Int {
    high.nonzeroBitCount + low.nonzeroBitCount
  }

  internal var byteSwapped: Self {
    Self(
      high: High(truncatingIfNeeded: low.byteSwapped),
      low: Low(truncatingIfNeeded: high.byteSwapped))
  }
}

extension _UInt128: Sendable {}
/// A 128-bit signed integer type.
internal struct _Int128 {
  internal typealias High = Int64
  internal typealias Low = UInt64

  /// The low part of the value.
  internal var low: Low

  /// The high part of the value.
  internal var high: High

  /// Creates a new instance from the given tuple of high and low parts.
  ///
  /// - Parameter value: The tuple to use as the source of the new instance's
  ///   high and low parts.
  internal init(_ value: (high: High, low: Low)) {
    self.low = value.low
    self.high = value.high
  }

  internal init(high: High, low: Low) {
    self.low = low
    self.high = high
  }

  internal init() {
    self.init(high: 0, low: 0)
  }

  internal init(bitPattern v: _UInt128) {
    self.init(high: High(bitPattern: v.high), low: v.low)
  }

  internal static var zero: Self { Self(high: 0, low: 0) }
  internal static var one: Self { Self(high: 0, low: 1) }
}

extension _Int128: CustomStringConvertible {
  internal var description: String {
    String(self, radix: 10)
  }
}

extension _Int128: CustomDebugStringConvertible {
  internal var debugDescription: String {
    description
  }
}

extension _Int128: Equatable {
  internal static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    return (lhs.high, lhs.low) == (rhs.high, rhs.low)
  }
}

extension _Int128: Comparable {
  internal static func < (_ lhs: Self, _ rhs: Self) -> Bool {
    (lhs.high, lhs.low) < (rhs.high, rhs.low)
  }
}

extension _Int128: Hashable {
  internal func hash(into hasher: inout Hasher) {
    hasher.combine(low)
    hasher.combine(high)
  }
}

extension _Int128 {
  internal var components: (high: High, low: Low) {
    @inline(__always) get { (high, low) }
    @inline(__always) set { (self.high, self.low) = (newValue.high, newValue.low) }
  }
}

extension _Int128: AdditiveArithmetic {
  internal static func - (_ lhs: Self, _ rhs: Self) -> Self {
    let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in -")
    return result
  }

  internal static func -= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in -=")
    lhs = result
  }

  internal static func + (_ lhs: Self, _ rhs: Self) -> Self {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in +")
    return result
  }

  internal static func += (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in +=")
    lhs = result
  }
}

extension _Int128: Numeric {
  internal typealias Magnitude = _UInt128

  internal var magnitude: Magnitude {
    var result = _UInt128(bitPattern: self)
    guard high._isNegative else { return result }
    result.high = ~result.high
    result.low = ~result.low
    return result.addingReportingOverflow(.one).partialValue
  }

  internal init(_ magnitude: Magnitude) {
    self.init(high: High(magnitude.high), low: magnitude.low)
  }

  internal init<T: BinaryInteger>(_ source: T) {
    guard let result = Self(exactly: source) else {
      preconditionFailure("Value is outside the representable range")
    }
    self = result
  }

  internal init?<T: BinaryInteger>(exactly source: T) {
    // Can't represent a negative 'source' if Self is unsigned.
    guard Self.isSigned || source >= 0 else {
      return nil
    }

    // Is 'source' entirely representable in Low?
    if let low = Low(exactly: source.magnitude) {
      self.init(source._isNegative ? (~0, low._twosComplement) : (0, low))
    } else {
      // At this point we know source.bitWidth > High.bitWidth, or else we
      // would've taken the first branch.
      let lowInT = source & T(~0 as Low)
      let highInT = source >> Low.bitWidth

      let low = Low(lowInT)
      guard let high = High(exactly: highInT) else {
        return nil
      }
      self.init(high: high, low: low)
    }
  }

  internal static func * (_ lhs: Self, _ rhs: Self) -> Self {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    precondition(!overflow, "Overflow in *")
    return result
  }

  internal static func *= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    precondition(!overflow, "Overflow in *=")
    lhs = result
  }
}

extension _Int128 {
  internal struct Words {
    internal var _value: _Int128

    internal init(_ value: _Int128) {
      self._value = value
    }
  }
}

extension _Int128.Words: RandomAccessCollection {
  internal typealias Element = UInt
  internal typealias Index = Int
  internal typealias Indices = Range<Int>
  internal typealias SubSequence = Slice<Self>

  internal var count: Int { 128 / UInt.bitWidth }
  internal var startIndex: Int { 0 }
  internal var endIndex: Int { count }
  internal var indices: Indices { startIndex ..< endIndex }
  internal func index(after i: Int) -> Int { i + 1 }
  internal func index(before i: Int) -> Int { i - 1 }

  internal subscript(position: Int) -> UInt {
    get {
      precondition(position >= 0 && position < endIndex,
        "Word index out of range")
      let shift = position &* UInt.bitWidth
      assert(shift < _Int128.bitWidth)

      let r = _wideMaskedShiftRight(
        _value.components, UInt64(truncatingIfNeeded: shift))
      return r.low._lowWord
    }
  }
}

extension _Int128: FixedWidthInteger {
  @_transparent
  internal var _lowWord: UInt {
    low._lowWord
  }

  internal var words: Words {
    Words(self)
  }

  internal static var isSigned: Bool {
    true
  }

  internal static var max: Self {
    self.init(high: High.max, low: Low.max)
  }

  internal static var min: Self {
    self.init(high: High.min, low: Low.min)
  }

  internal static var bitWidth: Int { 128 }

  internal func addingReportingOverflow(
    _ rhs: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideAddReportingOverflow22(self.components, rhs.components)
    return (Self(r), o)
  }

  internal func subtractingReportingOverflow(
    _ rhs: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideSubtractReportingOverflow22(
      self.components, rhs.components)
    return (Self(r), o)
  }

  internal func multipliedReportingOverflow(
    by rhs: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let isNegative = (self._isNegative != rhs._isNegative)
    let (p, overflow) = self.magnitude.multipliedReportingOverflow(
      by: rhs.magnitude)
    let r = _Int128(bitPattern: isNegative ? p._twosComplement : p)
    return (r, overflow || (isNegative != r._isNegative))
  }

  /// Returns the product of this value and the given 64-bit value, along with a
  /// Boolean value indicating whether overflow occurred in the operation.
  internal func multipliedReportingOverflow(
    by other: UInt64
  ) -> (partialValue: Self, overflow: Bool) {
    let isNegative = self._isNegative
    let (p, overflow) = self.magnitude.multipliedReportingOverflow(by: other)
    let r = _Int128(bitPattern: isNegative ? p._twosComplement : p)
    return (r, overflow || (isNegative != r._isNegative))
  }

  internal func multiplied(by other: UInt64) -> Self {
    let r = multipliedReportingOverflow(by: other)
    precondition(!r.overflow, "Overflow in multiplication")
    return r.partialValue
  }

  internal func quotientAndRemainder(
    dividingBy other: Self
  ) -> (quotient: Self, remainder: Self) {
    let (q, r) = _wideDivide22(
      self.magnitude.components, by: other.magnitude.components)
    let quotient = Self.Magnitude(q)
    let remainder = Self.Magnitude(r)
    let isNegative = (self.high._isNegative != other.high._isNegative)
    let quotient_ = (isNegative
      ? quotient == Self.min.magnitude ? Self.min : 0 - Self(quotient)
      : Self(quotient))
    let remainder_ = (self.high._isNegative
      ? 0 - Self(remainder)
      : Self(remainder))
    return (quotient_, remainder_)
  }

  internal func dividedReportingOverflow(
    by other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    if other == Self.zero {
      return (self, true)
    }
    if Self.isSigned && other == -1 && self == .min {
      return (self, true)
    }
    return (quotientAndRemainder(dividingBy: other).quotient, false)
  }

  internal func remainderReportingOverflow(
    dividingBy other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    if other == Self.zero {
      return (self, true)
    }
    if Self.isSigned && other == -1 && self == .min {
      return (0, true)
    }
    return (quotientAndRemainder(dividingBy: other).remainder, false)
  }

  internal func multipliedFullWidth(
    by other: Self
  ) -> (high: Self, low: Magnitude) {
    let isNegative = Self.isSigned && (self._isNegative != other._isNegative)

    func sum(_ x: Low, _ y: Low, _ z: Low) -> (high: Low, low: Low) {
      let (sum1, overflow1) = x.addingReportingOverflow(y)
      let (sum2, overflow2) = sum1.addingReportingOverflow(z)
      let carry: Low = (overflow1 ? 1 : 0) + (overflow2 ? 1 : 0)
      return (carry, sum2)
    }

    let lhs = self.magnitude
    let rhs = other.magnitude

    let a = rhs.low.multipliedFullWidth(by: lhs.low)
    let b = rhs.low.multipliedFullWidth(by: lhs.high)
    let c = rhs.high.multipliedFullWidth(by: lhs.low)
    let d = rhs.high.multipliedFullWidth(by: lhs.high)

    let mid1 = sum(a.high, b.low, c.low)
    let mid2 = sum(b.high, c.high, d.low)

    let low = _UInt128(high: mid1.low, low: a.low)
    let high = _Int128(
      high: High(mid2.high + d.high),
      low: mid1.high + mid2.low)

    if isNegative {
      let (lowComplement, overflow) = (~low).addingReportingOverflow(.one)
      return (~high + (overflow ? 1 : 0), lowComplement)
    } else {
      return (high, low)
    }
  }

  internal func dividingFullWidth(
    _ dividend: (high: Self, low: Self.Magnitude)
  ) -> (quotient: Self, remainder: Self) {
    let m = _wideMagnitude22(dividend)
    let (quotient, remainder) = self.magnitude.dividingFullWidth(m)

    let isNegative = (self.high._isNegative != dividend.high.high._isNegative)
    let quotient_ = (isNegative
      ? (quotient == Self.min.magnitude ? Self.min : 0 - Self(quotient))
      : Self(quotient))
    let remainder_ = (dividend.high.high._isNegative
      ? 0 - Self(remainder)
      : Self(remainder))
    return (quotient_, remainder_)
  }

  #if false // This triggers an unexpected type checking issue with `~0` in an
            // lldb test
  internal static prefix func ~(x: Self) -> Self {
    Self(high: ~x.high, low: ~x.low)
  }
  #endif

  internal static func &= (_ lhs: inout Self, _ rhs: Self) {
    lhs.low &= rhs.low
    lhs.high &= rhs.high
  }

  internal static func |= (_ lhs: inout Self, _ rhs: Self) {
    lhs.low |= rhs.low
    lhs.high |= rhs.high
  }

  internal static func ^= (_ lhs: inout Self, _ rhs: Self) {
    lhs.low ^= rhs.low
    lhs.high ^= rhs.high
  }

  internal static func <<= (_ lhs: inout Self, _ rhs: Self) {
    if Self.isSigned && rhs._isNegative {
      lhs >>= 0 - rhs
      return
    }

    // Shift is larger than this type's bit width.
    if rhs.high != High.zero || rhs.low >= Self.bitWidth {
      lhs = 0
      return
    }

    lhs &<<= rhs
  }

  internal static func >>= (_ lhs: inout Self, _ rhs: Self) {
    if Self.isSigned && rhs._isNegative {
      lhs <<= 0 - rhs
      return
    }

    // Shift is larger than this type's bit width.
    if rhs.high != High.zero || rhs.low >= Self.bitWidth {
      lhs = lhs._isNegative ? ~0 : 0
      return
    }

    lhs &>>= rhs
  }

  internal static func &<< (lhs: Self, rhs: Self) -> Self {
    Self(_wideMaskedShiftLeft(lhs.components, rhs.low))
  }

  internal static func &>> (lhs: Self, rhs: Self) -> Self {
    Self(_wideMaskedShiftRight(lhs.components, rhs.low))
  }

  internal static func &<<= (lhs: inout Self, rhs: Self) {
    _wideMaskedShiftLeft(&lhs.components, rhs.low)
  }

  internal static func &>>= (lhs: inout Self, rhs: Self) {
    _wideMaskedShiftRight(&lhs.components, rhs.low)
  }

  internal static func / (
    _ lhs: Self, _ rhs: Self
  ) -> Self {
    var lhs = lhs
    lhs /= rhs
    return lhs
  }

  internal static func /= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.dividedReportingOverflow(by: rhs)
    precondition(!overflow, "Overflow in /=")
    lhs = result
  }

  internal static func % (
    _ lhs: Self, _ rhs: Self
  ) -> Self {
    var lhs = lhs
    lhs %= rhs
    return lhs
  }

  internal static func %= (_ lhs: inout Self, _ rhs: Self) {
    let (result, overflow) = lhs.remainderReportingOverflow(dividingBy: rhs)
    precondition(!overflow, "Overflow in %=")
    lhs = result
  }

  internal init(_truncatingBits bits: UInt) {
    low = Low(_truncatingBits: bits)
    high = High(_truncatingBits: bits >> UInt(Low.bitWidth))
  }

  internal init(integerLiteral x: Int64) {
    self.init(x)
  }

  internal var leadingZeroBitCount: Int {
    (high == High.zero
      ? High.bitWidth + low.leadingZeroBitCount
      : high.leadingZeroBitCount)
  }

  internal var trailingZeroBitCount: Int {
    (low == Low.zero
      ? Low.bitWidth + high.trailingZeroBitCount
      : low.trailingZeroBitCount)
  }

  internal var nonzeroBitCount: Int {
    high.nonzeroBitCount + low.nonzeroBitCount
  }

  internal var byteSwapped: Self {
    Self(
      high: High(truncatingIfNeeded: low.byteSwapped),
      low: Low(truncatingIfNeeded: high.byteSwapped))
  }
}

extension _Int128: Sendable {}

extension BinaryInteger {
  @inline(__always)
  fileprivate var _isNegative: Bool { self < Self.zero }
}

extension FixedWidthInteger {
  @inline(__always)
  fileprivate var _twosComplement: Self {
    ~self &+ 1
  }
}

private typealias _Wide2<F: FixedWidthInteger> =
  (high: F, low: F.Magnitude)

private typealias _Wide3<F: FixedWidthInteger> =
  (high: F, mid: F.Magnitude, low: F.Magnitude)

private typealias _Wide4<F: FixedWidthInteger> =
  (high: _Wide2<F>, low: (high: F.Magnitude, low: F.Magnitude))

private func _wideMagnitude22<F: FixedWidthInteger>(
  _ v: _Wide2<F>
) -> _Wide2<F.Magnitude> {
  var result = (high: F.Magnitude(truncatingIfNeeded: v.high), low: v.low)
  guard F.isSigned && v.high._isNegative else { return result }
  result.high = ~result.high
  result.low = ~result.low
  return _wideAddReportingOverflow22(result, (high: 0, low: 1)).partialValue
}

private func _wideAddReportingOverflow22<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: _Wide2<F>
) -> (partialValue: _Wide2<F>, overflow: Bool) {
  let (low, lowOverflow) = lhs.low.addingReportingOverflow(rhs.low)
  let (high, highOverflow) = lhs.high.addingReportingOverflow(rhs.high)
  let overflow = highOverflow || high == F.max && lowOverflow
  let result = (high: high &+ (lowOverflow ? 1 : 0), low: low)
  return (partialValue: result, overflow: overflow)
}

private func _wideAdd22<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: _Wide2<F>
) {
  let (result, overflow) = _wideAddReportingOverflow22(lhs, rhs)
  precondition(!overflow, "Overflow in +")
  lhs = result
}

private func _wideAddReportingOverflow33<F: FixedWidthInteger>(
  _ lhs: _Wide3<F>, _ rhs: _Wide3<F>
) -> (
  partialValue: _Wide3<F>,
  overflow: Bool
) {
  let (low, lowOverflow) =
    _wideAddReportingOverflow22((lhs.mid, lhs.low), (rhs.mid, rhs.low))
  let (high, highOverflow) = lhs.high.addingReportingOverflow(rhs.high)
  let result = (high: high &+ (lowOverflow ? 1 : 0), mid: low.high, low: low.low)
  let overflow = highOverflow || (high == F.max && lowOverflow)
  return (partialValue: result, overflow: overflow)
}

private func _wideSubtractReportingOverflow22<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: _Wide2<F>
) -> (partialValue: (high: F, low: F.Magnitude), overflow: Bool) {
  let (low, lowOverflow) = lhs.low.subtractingReportingOverflow(rhs.low)
  let (high, highOverflow) = lhs.high.subtractingReportingOverflow(rhs.high)
  let result = (high: high &- (lowOverflow ? 1 : 0), low: low)
  let overflow = highOverflow || high == F.min && lowOverflow
  return (partialValue: result, overflow: overflow)
}

private func _wideSubtract22<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: _Wide2<F>
) {
  let (result, overflow) = _wideSubtractReportingOverflow22(lhs, rhs)
  precondition(!overflow, "Overflow in -")
  lhs = result
}

private func _wideSubtractReportingOverflow33<F: FixedWidthInteger>(
  _ lhs: _Wide3<F>, _ rhs: _Wide3<F>
) -> (
  partialValue: _Wide3<F>,
  overflow: Bool
) {
  let (low, lowOverflow) =
    _wideSubtractReportingOverflow22((lhs.mid, lhs.low), (rhs.mid, rhs.low))
  let (high, highOverflow) = lhs.high.subtractingReportingOverflow(rhs.high)
  let result = (high: high &- (lowOverflow ? 1 : 0), mid: low.high, low: low.low)
  let overflow = highOverflow || (high == F.min && lowOverflow)
  return (partialValue: result, overflow: overflow)
}

private func _wideMaskedShiftLeft<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: F.Magnitude
) -> _Wide2<F> {
  let bitWidth = F.bitWidth + F.Magnitude.bitWidth
  assert(bitWidth.nonzeroBitCount == 1)

  // Mask rhs by the bit width of the wide value.
  let rhs = rhs & F.Magnitude(bitWidth &- 1)

  guard rhs < F.Magnitude.bitWidth else {
    let s = rhs &- F.Magnitude(F.Magnitude.bitWidth)
    return (high: F(truncatingIfNeeded: lhs.low &<< s), low: 0)
  }

  guard rhs != F.Magnitude.zero else { return lhs }
  var high = lhs.high &<< F(rhs)
  let rollover = F.Magnitude(F.bitWidth) &- rhs
  high |= F(truncatingIfNeeded: lhs.low &>> rollover)
  let low = lhs.low &<< rhs
  return (high, low)
}

private func _wideMaskedShiftLeft<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: F.Magnitude
) {
  lhs = _wideMaskedShiftLeft(lhs, rhs)
}

private func _wideMaskedShiftRight<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: F.Magnitude
) -> _Wide2<F> {
  let bitWidth = F.bitWidth + F.Magnitude.bitWidth
  assert(bitWidth.nonzeroBitCount == 1)

  // Mask rhs by the bit width of the wide value.
  let rhs = rhs & F.Magnitude(bitWidth &- 1)

  guard rhs < F.bitWidth else {
    let s = F(rhs &- F.Magnitude(F.bitWidth))
    return (
      high: lhs.high._isNegative ? ~0 : 0,
      low: F.Magnitude(truncatingIfNeeded: lhs.high &>> s))
  }

  guard rhs != F.zero else { return lhs }
  var low = lhs.low &>> rhs
  let rollover = F(F.bitWidth) &- F(rhs)
  low |= F.Magnitude(truncatingIfNeeded: lhs.high &<< rollover)
  let high = lhs.high &>> rhs
  return (high, low)
}

private func _wideMaskedShiftRight<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: F.Magnitude
) {
  lhs = _wideMaskedShiftRight(lhs, rhs)
}

/// Returns the quotient and remainder after dividing a triple-width magnitude
/// `lhs` by a double-width magnitude `rhs`.
///
/// This operation is conceptually that described by Burnikel and Ziegler
/// (1998).
private func _wideDivide32<F: FixedWidthInteger & UnsignedInteger>(
  _ lhs: _Wide3<F>, by rhs: _Wide2<F>
) -> (quotient: F, remainder: _Wide2<F>) {
  // The following invariants are guaranteed to hold by dividingFullWidth or
  // quotientAndRemainder before this function is invoked:
  assert(lhs.high != F.zero)
  assert(rhs.high.leadingZeroBitCount == 0)
  assert((high: lhs.high, low: lhs.mid) < rhs)

  // Estimate the quotient with a 2/1 division using just the top digits.
  var quotient = (lhs.high == rhs.high
    ? F.max
    : rhs.high.dividingFullWidth((high: lhs.high, low: lhs.mid)).quotient)

  // Compute quotient * rhs.
  // TODO: This could be performed more efficiently.
  let p1 = quotient.multipliedFullWidth(by: F(rhs.low))
  let p2 = quotient.multipliedFullWidth(by: rhs.high)
  let product = _wideAddReportingOverflow33(
    (high: F.zero, mid: F.Magnitude(p1.high), low: p1.low),
    (high: p2.high, mid: p2.low, low: .zero)).partialValue

  // Compute the remainder after decrementing quotient as necessary.
  var remainder = lhs

  while remainder < product {
    quotient = quotient &- 1
    remainder = _wideAddReportingOverflow33(
      remainder,
      (high: F.zero, mid: F.Magnitude(rhs.high), low: rhs.low)).partialValue
  }
  remainder = _wideSubtractReportingOverflow33(remainder, product).partialValue
  assert(remainder.high == 0)
  return (quotient, (high: F(remainder.mid), low: remainder.low))
}

/// Returns the quotient and remainder after dividing a double-width
/// magnitude `lhs` by a double-width magnitude `rhs`.
private func _wideDivide22<F: FixedWidthInteger & UnsignedInteger>(
  _ lhs: _Wide2<F>, by rhs: _Wide2<F>
) -> (quotient: _Wide2<F>, remainder: _Wide2<F>) {
  guard _fastPath(rhs > (F.zero, F.Magnitude.zero)) else {
    fatalError("Division by zero")
  }
  guard rhs < lhs else {
    if _fastPath(rhs > lhs) { return (quotient: (0, 0), remainder: lhs) }
    return (quotient: (0, 1), remainder: (0, 0))
  }

  if lhs.high == F.zero {
    let (quotient, remainder) =
      lhs.low.quotientAndRemainder(dividingBy: rhs.low)
    return ((0, quotient), (0, remainder))
  }

  if rhs.high == F.zero {
    let (x, a) = lhs.high.quotientAndRemainder(dividingBy: F(rhs.low))
    let (y, b) = (a == F.zero
      ? lhs.low.quotientAndRemainder(dividingBy: rhs.low)
      : rhs.low.dividingFullWidth((F.Magnitude(a), lhs.low)))
    return (quotient: (high: x, low: y), remainder: (high: 0, low: b))
  }

  // Left shift both rhs and lhs, then divide and right shift the remainder.
  let shift = F.Magnitude(rhs.high.leadingZeroBitCount)
  let rollover = F.Magnitude(F.bitWidth + F.Magnitude.bitWidth) &- shift
  let rhs = _wideMaskedShiftLeft(rhs, shift)
  let high = _wideMaskedShiftRight(lhs, rollover).low
  let lhs = _wideMaskedShiftLeft(lhs, shift)
  let (quotient, remainder) = _wideDivide32(
    (F(high), F.Magnitude(lhs.high), lhs.low), by: rhs)
  return (
    quotient: (high: 0, low: F.Magnitude(quotient)),
    remainder: _wideMaskedShiftRight(remainder, shift))
}

/// Returns the quotient and remainder after dividing a quadruple-width
/// magnitude `lhs` by a double-width magnitude `rhs`.
private func _wideDivide42<F: FixedWidthInteger & UnsignedInteger>(
  _ lhs: _Wide4<F>, by rhs: _Wide2<F>
) -> (quotient: _Wide2<F>, remainder: _Wide2<F>) {
  guard _fastPath(rhs > (F.zero, F.Magnitude.zero)) else {
    fatalError("Division by zero")
  }
  guard _fastPath(rhs >= lhs.high) else {
    fatalError("Division results in an overflow")
  }

  if lhs.high == (F.zero, F.Magnitude.zero) {
    return _wideDivide22((high: F(lhs.low.high), low: lhs.low.low), by: rhs)
  }

  if rhs.high == F.zero {
    let a = F.Magnitude(lhs.high.high) % rhs.low
    let b = (a == F.Magnitude.zero
      ? lhs.high.low % rhs.low
      : rhs.low.dividingFullWidth((a, lhs.high.low)).remainder)
    let (x, c) = (b == F.Magnitude.zero
      ? lhs.low.high.quotientAndRemainder(dividingBy: rhs.low)
      : rhs.low.dividingFullWidth((b, lhs.low.high)))
    let (y, d) = (c == F.Magnitude.zero
      ? lhs.low.low.quotientAndRemainder(dividingBy: rhs.low)
      : rhs.low.dividingFullWidth((c, lhs.low.low)))
    return (quotient: (high: F(x), low: y), remainder: (high: 0, low: d))
  }

  // Left shift both rhs and lhs, then divide and right shift the remainder.
  let shift = F.Magnitude(rhs.high.leadingZeroBitCount)
  let rollover = F.Magnitude(F.bitWidth + F.Magnitude.bitWidth) &- shift
  let rhs = _wideMaskedShiftLeft(rhs, shift)

  let lh1 = _wideMaskedShiftLeft(lhs.high, shift)
  let lh2 = _wideMaskedShiftRight(lhs.low, rollover)
  let lhs = (
    high: (high: lh1.high | F(lh2.high), low: lh1.low | lh2.low),
    low: _wideMaskedShiftLeft(lhs.low, shift))

  if
    lhs.high.high == F.Magnitude.zero,
    (high: F(lhs.high.low), low: lhs.low.high) < rhs
  {
    let (quotient, remainder) = _wideDivide32(
      (F(lhs.high.low), lhs.low.high, lhs.low.low),
      by: rhs)
    return (
      quotient: (high: 0, low: F.Magnitude(quotient)),
      remainder: _wideMaskedShiftRight(remainder, shift))
  }
  let (x, a) = _wideDivide32(
    (lhs.high.high, lhs.high.low, lhs.low.high), by: rhs)
  let (y, b) = _wideDivide32((a.high, a.low, lhs.low.low), by: rhs)
  return (
    quotient: (high: x, low: F.Magnitude(y)),
    remainder: _wideMaskedShiftRight(b, shift))
}


extension _UInt128: UnsignedInteger {}
extension _Int128: SignedNumeric, SignedInteger {}


extension _Int128 {
  internal func dividedBy1e18() -> (quotient: Self, remainder: Self) {
    let m = _Int128(high: 664613997892457936, low: 8336148766501648893)
    var q = self.multipliedFullWidth(by: m).high
    q &>>= 55
    // Add 1 to q if self is negative
    q &+= _Int128(bitPattern: _UInt128(bitPattern: self) &>> 127)
    let r = self &- q &* (1000000000000000000 as _Int128)
    return (q, r)
  }
}
extension _Int128 {
  internal func dividedBy1e15() -> (quotient: Self, remainder: Self) {
    let m = _Int128(high: -8062150356639896359, low: 1125115960621402641)
    var q = self.multipliedFullWidth(by: m).high
    q &+= self
    q &>>= 49
    // Add 1 to q if self is negative
    q &+= _Int128(bitPattern: _UInt128(bitPattern: self) &>> 127)
    let r = self &- q &* (1000000000000000 as _Int128)
    return (q, r)
  }
}
extension _Int128 {
  internal func dividedBy1e12() -> (quotient: Self, remainder: Self) {
    let m = _Int128(high: 2535301200456458802, low: 18325113820324532597)
    var q = self.multipliedFullWidth(by: m).high
    q &>>= 37
    // Add 1 to q if self is negative
    q &+= _Int128(bitPattern: _UInt128(bitPattern: self) &>> 127)
    let r = self &- q &* (1000000000000 as _Int128)
    return (q, r)
  }
}
extension _Int128 {
  internal func dividedBy1e9() -> (quotient: Self, remainder: Self) {
    let m = _Int128(high: 4951760157141521099, low: 11003425581274142745)
    var q = self.multipliedFullWidth(by: m).high
    q &>>= 28
    // Add 1 to q if self is negative
    q &+= _Int128(bitPattern: _UInt128(bitPattern: self) &>> 127)
    let r = self &- q &* (1000000000 as _Int128)
    return (q, r)
  }
}
extension _Int128 {
  internal func dividedBy1e6() -> (quotient: Self, remainder: Self) {
    let m = _Int128(high: 604462909807314587, low: 6513323971497958161)
    var q = self.multipliedFullWidth(by: m).high
    q &>>= 15
    // Add 1 to q if self is negative
    q &+= _Int128(bitPattern: _UInt128(bitPattern: self) &>> 127)
    let r = self &- q &* (1000000 as _Int128)
    return (q, r)
  }
}
extension _Int128 {
  internal func dividedBy1e3() -> (quotient: Self, remainder: Self) {
    let m = _Int128(high: 4722366482869645213, low: 12838933875301847925)
    var q = self.multipliedFullWidth(by: m).high
    q &>>= 8
    // Add 1 to q if self is negative
    q &+= _Int128(bitPattern: _UInt128(bitPattern: self) &>> 127)
    let r = self &- q &* (1000 as _Int128)
    return (q, r)
  }
}

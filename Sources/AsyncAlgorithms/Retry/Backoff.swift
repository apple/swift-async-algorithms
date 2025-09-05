import _CPowSupport

#if compiler(<6.2)
@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension Duration {
  @usableFromInline var attoseconds: Int128 {
    return Int128(_low: _low, _high: _high)
  }
  @usableFromInline init(attoseconds: Int128) {
    self.init(_high: attoseconds._high, low: attoseconds._low)
  }
}
#endif

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public protocol BackoffStrategy<Duration> {
  associatedtype Duration: DurationProtocol
  mutating func duration(_ attempt: Int) -> Duration
  mutating func duration(_ attempt: Int, using generator: inout some RandomNumberGenerator) -> Duration
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
extension BackoffStrategy {
  @inlinable public mutating func duration(_ attempt: Int, using generator: inout some RandomNumberGenerator) -> Duration {
    return duration(attempt)
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline
struct ConstantBackoffStrategy<Duration: DurationProtocol>: BackoffStrategy {
  @usableFromInline let c: Duration
  @usableFromInline init(c: Duration) {
    self.c = c
  }
  @inlinable func duration(_ attempt: Int) -> Duration {
    return c
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline
struct LinearBackoffStrategy<Duration: DurationProtocol>: BackoffStrategy {
  @usableFromInline let a: Duration
  @usableFromInline let b: Duration
  @usableFromInline init(a: Duration, b: Duration) {
    self.a = a
    self.b = b
  }
  @inlinable func duration(_ attempt: Int) -> Duration {
    return a * attempt + b
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline struct ExponentialBackoffStrategy: BackoffStrategy {
  @usableFromInline let a: Duration
  @usableFromInline let b: Double
  @usableFromInline init(a: Duration, b: Double) {
    self.a = a
    self.b = b
  }
  @inlinable func duration(_ attempt: Int) -> Duration {
    return a * pow(b, Double(attempt))
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline
struct MinimumBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy {
  @usableFromInline var base: Base
  @usableFromInline let minimum: Base.Duration
  @usableFromInline init(base: Base, minimum: Base.Duration) {
    self.base = base
    self.minimum = minimum
  }
  @inlinable mutating func duration(_ attempt: Int) -> Base.Duration {
    return max(minimum, base.duration(attempt))
  }
  @inlinable mutating func duration(_ attempt: Int, using generator: inout some RandomNumberGenerator) -> Base.Duration {
    return max(minimum, base.duration(attempt, using: &generator))
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline
struct MaximumBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy {
  @usableFromInline var base: Base
  @usableFromInline let maximum: Base.Duration
  @usableFromInline init(base: Base, maximum: Base.Duration) {
    self.base = base
    self.maximum = maximum
  }
  @inlinable mutating func duration(_ attempt: Int) -> Base.Duration {
    return min(maximum, base.duration(attempt))
  }
  @inlinable mutating func duration(_ attempt: Int, using generator: inout some RandomNumberGenerator) -> Base.Duration {
    return min(maximum, base.duration(attempt, using: &generator))
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
@usableFromInline
struct FullJitterBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy where Base.Duration == Swift.Duration {
  @usableFromInline var base: Base
  @usableFromInline init(base: Base) {
    self.base = base
  }
  @inlinable mutating func duration(_ attempt: Int) -> Base.Duration {
    return .init(attoseconds: Int128.random(in: 0...base.duration(attempt).attoseconds))
  }
  @inlinable mutating func duration(_ attempt: Int, using generator: inout some RandomNumberGenerator) -> Base.Duration {
    return .init(attoseconds: Int128.random(in: 0...base.duration(attempt, using: &generator).attoseconds, using: &generator))
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
@usableFromInline
struct EqualJitterBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy where Base.Duration == Swift.Duration {
  @usableFromInline var base: Base
  @usableFromInline init(base: Base) {
    self.base = base
  }
  @inlinable mutating func duration(_ attempt: Int) -> Base.Duration {
    let halfBase = (base.duration(attempt) / 2).attoseconds
    return .init(attoseconds: halfBase + Int128.random(in: 0...halfBase))
  }
  @inlinable mutating func duration(_ attempt: Int, using generator: inout some RandomNumberGenerator) -> Base.Duration {
    let halfBase = (base.duration(attempt, using: &generator) / 2).attoseconds
    return .init(attoseconds: halfBase + Int128.random(in: 0...halfBase, using: &generator))
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
@usableFromInline
struct DecorrelatedJitterBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy where Base.Duration == Swift.Duration {
  @usableFromInline var base: Base
  @usableFromInline let divisor: Int128
  @usableFromInline var previousDuration: Duration?
  @usableFromInline init(base: Base, divisor: Int128) {
    self.base = base
    self.divisor = divisor
  }
  @inlinable mutating func duration(_ attempt: Int) -> Base.Duration {
    let base = base.duration(attempt)
    let previousDuration = previousDuration ?? base
    self.previousDuration = previousDuration
    return .init(attoseconds: Int128.random(in: base.attoseconds...previousDuration.attoseconds / divisor))
  }
  @inlinable mutating func duration(_ attempt: Int, using generator: inout some RandomNumberGenerator) -> Base.Duration {
    let base = base.duration(attempt, using: &generator)
    let previousDuration = previousDuration ?? base
    self.previousDuration = previousDuration
    return .init(attoseconds: Int128.random(in: base.attoseconds...previousDuration.attoseconds / divisor, using: &generator))
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public enum Backoff {
  @inlinable public static func constant<Duration: DurationProtocol>(_ c: Duration) -> some BackoffStrategy<Duration> {
    return ConstantBackoffStrategy(c: c)
  }
  @inlinable public static func constant(_ c: Duration) -> some BackoffStrategy<Duration> {
    return ConstantBackoffStrategy(c: c)
  }
  @inlinable public static func linear<Duration: DurationProtocol>(increment a: Duration, initial b: Duration) -> some BackoffStrategy<Duration> {
    return LinearBackoffStrategy(a: a, b: b)
  }
  @inlinable public static func linear(increment a: Duration, initial b: Duration) -> some BackoffStrategy<Duration> {
    return LinearBackoffStrategy(a: a, b: b)
  }
  @inlinable public static func exponential(multiplier b: Double = 2, initial a: Duration) -> some BackoffStrategy<Duration> {
    return ExponentialBackoffStrategy(a: a, b: b)
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
extension BackoffStrategy {
  @inlinable public func minimum(_ minimum: Duration) -> some BackoffStrategy<Duration> {
    return MinimumBackoffStrategy(base: self, minimum: minimum)
  }
  @inlinable public func maximum(_ maximum: Duration) -> some BackoffStrategy<Duration> {
    return MaximumBackoffStrategy(base: self, maximum: maximum)
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension BackoffStrategy where Duration == Swift.Duration {
  @inlinable public func fullJitter() -> some BackoffStrategy<Duration> {
    return FullJitterBackoffStrategy(base: self)
  }
  @inlinable public func equalJitter() -> some BackoffStrategy<Duration> {
    return EqualJitterBackoffStrategy(base: self)
  }
  @inlinable public func decorrelatedJitter(divisor: Int = 3) -> some BackoffStrategy<Duration> {
    return DecorrelatedJitterBackoffStrategy(base: self, divisor: Int128(divisor))
  }
}

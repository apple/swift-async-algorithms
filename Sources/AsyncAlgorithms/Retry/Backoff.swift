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
  mutating func nextDuration() -> Duration
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline struct ConstantBackoffStrategy<Duration: DurationProtocol>: BackoffStrategy {
  @usableFromInline let constant: Duration
  @usableFromInline init(constant: Duration) {
    precondition(constant >= .zero, "Constant must be greater than or equal to 0")
    self.constant = constant
  }
  @inlinable func nextDuration() -> Duration {
    return constant
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline struct LinearBackoffStrategy<Duration: DurationProtocol>: BackoffStrategy {
  @usableFromInline var current: Duration
  @usableFromInline let increment: Duration
  @usableFromInline init(increment: Duration, initial: Duration) {
    precondition(initial >= .zero, "Initial must be greater than or equal to 0")
    precondition(increment >= .zero, "Increment must be greater than or equal to 0")
    self.current = initial
    self.increment = increment
  }
  @inlinable mutating func nextDuration() -> Duration {
    defer { current += increment }
    return current
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline struct ExponentialBackoffStrategy<Duration: DurationProtocol>: BackoffStrategy {
  @usableFromInline var current: Duration
  @usableFromInline let factor: Int
  @usableFromInline init(factor: Int, initial: Duration) {
    precondition(initial >= .zero, "Initial must be greater than or equal to 0")
    precondition(factor >= 1, "Factor must be greater than or equal to 1")
    self.current = initial
    self.factor = factor
  }
  @inlinable mutating func nextDuration() -> Duration {
    defer { current *= factor }
    return current
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline struct MinimumBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy {
  @usableFromInline var base: Base
  @usableFromInline let minimum: Base.Duration
  @usableFromInline init(base: Base, minimum: Base.Duration) {
    self.base = base
    self.minimum = minimum
  }
  @inlinable mutating func nextDuration() -> Base.Duration {
    return max(minimum, base.nextDuration())
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@usableFromInline struct MaximumBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy {
  @usableFromInline var base: Base
  @usableFromInline let maximum: Base.Duration
  @usableFromInline init(base: Base, maximum: Base.Duration) {
    self.base = base
    self.maximum = maximum
  }
  @inlinable mutating func nextDuration() -> Base.Duration {
    return min(maximum, base.nextDuration())
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
@usableFromInline struct FullJitterBackoffStrategy<Base: BackoffStrategy, RNG: RandomNumberGenerator>: BackoffStrategy where Base.Duration == Swift.Duration {
  @usableFromInline var base: Base
  @usableFromInline var generator: RNG
  @usableFromInline init(base: Base, generator: RNG) {
    self.base = base
    self.generator = generator
  }
  @inlinable mutating func nextDuration() -> Base.Duration {
    return .init(attoseconds: Int128.random(in: 0...base.nextDuration().attoseconds, using: &generator))
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
@usableFromInline struct EqualJitterBackoffStrategy<Base: BackoffStrategy, RNG: RandomNumberGenerator>: BackoffStrategy where Base.Duration == Swift.Duration {
  @usableFromInline var base: Base
  @usableFromInline var generator: RNG
  @usableFromInline init(base: Base, generator: RNG) {
    self.base = base
    self.generator = generator
  }
  @inlinable mutating func nextDuration() -> Base.Duration {
    let base = base.nextDuration()
    return .init(attoseconds: Int128.random(in: (base / 2).attoseconds...base.attoseconds, using: &generator))
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
@usableFromInline struct DecorrelatedJitterBackoffStrategy<RNG: RandomNumberGenerator>: BackoffStrategy {
  @usableFromInline let base: Duration
  @usableFromInline let factor: Int
  @usableFromInline var generator: RNG
  @usableFromInline var current: Duration?
  @usableFromInline init(base: Duration, factor: Int, generator: RNG) {
    precondition(factor >= 1, "Factor must be greater than or equal to 1")
    precondition(base >= .zero, "Base must be greater than or equal to 0")
    self.base = base
    self.generator = generator
    self.factor = factor
  }
  @inlinable mutating func nextDuration() -> Duration {
    let previous = current ?? base
    let next = Duration(attoseconds: Int128.random(in: base.attoseconds...(previous * factor).attoseconds, using: &generator))
    current = next
    return next
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public enum Backoff {
  @inlinable public static func constant<Duration: DurationProtocol>(_ constant: Duration) -> some BackoffStrategy<Duration> {
    return ConstantBackoffStrategy(constant: constant)
  }
  @inlinable public static func constant(_ constant: Duration) -> some BackoffStrategy<Duration> {
    return ConstantBackoffStrategy(constant: constant)
  }
  @inlinable public static func linear<Duration: DurationProtocol>(increment: Duration, initial: Duration) -> some BackoffStrategy<Duration> {
    return LinearBackoffStrategy(increment: increment, initial: initial)
  }
  @inlinable public static func linear(increment: Duration, initial: Duration) -> some BackoffStrategy<Duration> {
    return LinearBackoffStrategy(increment: increment, initial: initial)
  }
  @inlinable public static func exponential<Duration: DurationProtocol>(factor: Int, initial: Duration) -> some BackoffStrategy<Duration> {
    return ExponentialBackoffStrategy(factor: factor, initial: initial)
  }
  @inlinable public static func exponential(factor: Int, initial: Duration) -> some BackoffStrategy<Duration> {
    return ExponentialBackoffStrategy(factor: factor, initial: initial)
  }
  @inlinable public static func decorrelatedJitter<RNG: RandomNumberGenerator>(factor: Int, base: Duration, using generator: RNG) -> some BackoffStrategy<Duration> {
    return DecorrelatedJitterBackoffStrategy(base: base, factor: factor, generator: generator)
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
  @inlinable public func fullJitter<RNG: RandomNumberGenerator>(using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration> {
    return FullJitterBackoffStrategy(base: self, generator: generator)
  }
  @inlinable public func equalJitter<RNG: RandomNumberGenerator>(using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration> {
    return EqualJitterBackoffStrategy(base: self, generator: generator)
  }
}

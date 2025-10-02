#if compiler(>=6.2)
/// A protocol for defining backoff strategies that generate delays between retry attempts.
///
/// Each call to `nextDuration()` returns the delay for the next retry attempt. Strategies are
/// naturally stateful. For instance, they may track the number of invocations or the previously
/// returned duration to calculate the next delay.
///
/// - Precondition: Strategies should only increase or stay the same over time, never decrease.
///   Decreasing delays may cause issues with modifiers like jitter which expect non-decreasing values.
///
/// ## Example
///
/// ```swift
/// var strategy = Backoff.exponential(factor: 2, initial: .milliseconds(100))
/// strategy.nextDuration() // 100ms
/// strategy.nextDuration() // 200ms
/// strategy.nextDuration() // 400ms
/// ```
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
  /// Creates a constant backoff strategy that always returns the same delay.
  ///
  /// Formula: `f(n) = constant`
  ///
  /// - Precondition: `constant` must be greater than or equal to zero.
  ///
  /// - Parameter constant: The fixed duration to wait between retry attempts.
  /// - Returns: A backoff strategy that always returns the constant duration.
  @inlinable public static func constant<Duration: DurationProtocol>(_ constant: Duration) -> some BackoffStrategy<Duration> {
    return ConstantBackoffStrategy(constant: constant)
  }

  /// Creates a constant backoff strategy that always returns the same delay.
  ///
  /// Formula: `f(n) = constant`
  ///
  /// - Precondition: `constant` must be greater than or equal to zero.
  ///
  /// - Parameter constant: The fixed duration to wait between retry attempts.
  /// - Returns: A backoff strategy that always returns the constant duration.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var backoff = Backoff.constant(.milliseconds(100))
  /// backoff.nextDuration() // 100ms
  /// backoff.nextDuration() // 100ms
  /// ```
  @inlinable public static func constant(_ constant: Duration) -> some BackoffStrategy<Duration> {
    return ConstantBackoffStrategy(constant: constant)
  }

  /// Creates a linear backoff strategy where delays increase by a fixed increment.
  ///
  /// Formula: `f(n) = initial + increment * n`
  ///
  /// - Precondition: `initial` and `increment` must be greater than or equal to zero.
  ///
  /// - Parameters:
  ///   - increment: The amount to increase the delay by on each attempt.
  ///   - initial: The initial delay for the first retry attempt.
  /// - Returns: A backoff strategy with linearly increasing delays.
  @inlinable public static func linear<Duration: DurationProtocol>(increment: Duration, initial: Duration) -> some BackoffStrategy<Duration> {
    return LinearBackoffStrategy(increment: increment, initial: initial)
  }

  /// Creates a linear backoff strategy where delays increase by a fixed increment.
  ///
  /// Formula: `f(n) = initial + increment * n`
  ///
  /// - Precondition: `initial` and `increment` must be greater than or equal to zero.
  ///
  /// - Parameters:
  ///   - increment: The amount to increase the delay by on each attempt.
  ///   - initial: The initial delay for the first retry attempt.
  /// - Returns: A backoff strategy with linearly increasing delays.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var backoff = Backoff.linear(increment: .milliseconds(100), initial: .milliseconds(100))
  /// backoff.nextDuration() // 100ms
  /// backoff.nextDuration() // 200ms
  /// backoff.nextDuration() // 300ms
  /// ```
  @inlinable public static func linear(increment: Duration, initial: Duration) -> some BackoffStrategy<Duration> {
    return LinearBackoffStrategy(increment: increment, initial: initial)
  }

  /// Creates an exponential backoff strategy where delays grow exponentially.
  ///
  /// Formula: `f(n) = initial * factor^n`
  ///
  /// - Precondition: `initial` must be greater than or equal to zero.
  ///
  /// - Parameters:
  ///   - factor: The multiplication factor for each retry attempt.
  ///   - initial: The initial delay for the first retry attempt.
  /// - Returns: A backoff strategy with exponentially increasing delays.
  @inlinable public static func exponential<Duration: DurationProtocol>(factor: Int, initial: Duration) -> some BackoffStrategy<Duration> {
    return ExponentialBackoffStrategy(factor: factor, initial: initial)
  }

  /// Creates an exponential backoff strategy where delays grow exponentially.
  ///
  /// Formula: `f(n) = initial * factor^n`
  ///
  /// - Precondition: `initial` must be greater than or equal to zero.
  ///
  /// - Parameters:
  ///   - factor: The multiplication factor for each retry attempt.
  ///   - initial: The initial delay for the first retry attempt.
  /// - Returns: A backoff strategy with exponentially increasing delays.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var backoff = Backoff.exponential(factor: 2, initial: .milliseconds(100))
  /// backoff.nextDuration() // 100ms
  /// backoff.nextDuration() // 200ms
  /// backoff.nextDuration() // 400ms
  /// ```
  @inlinable public static func exponential(factor: Int, initial: Duration) -> some BackoffStrategy<Duration> {
    return ExponentialBackoffStrategy(factor: factor, initial: initial)
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension Backoff {
  /// Creates a decorrelated jitter backoff strategy that uses randomized delays.
  ///
  /// Formula: `f(n) = random(base, f(n - 1) * factor)` where `f(0) = base`
  ///
  /// Jitter prevents the thundering herd problem where multiple clients retry
  /// simultaneously, reducing server load spikes and improving system stability.
  ///
  /// - Precondition: `factor` must be greater than or equal to 1, and `base` must be greater than or equal to zero.
  ///
  /// - Parameters:
  ///   - factor: The multiplication factor for calculating the upper bound of randomness.
  ///   - base: The base duration used as the minimum delay and initial reference.
  ///   - generator: The random number generator to use. Defaults to `SystemRandomNumberGenerator()`.
  /// - Returns: A backoff strategy with decorrelated jitter.
  @inlinable public static func decorrelatedJitter<RNG: RandomNumberGenerator>(factor: Int, base: Duration, using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration> {
    return DecorrelatedJitterBackoffStrategy(base: base, factor: factor, generator: generator)
  }
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
extension BackoffStrategy {
  /// Applies a minimum duration constraint to this backoff strategy.
  ///
  /// Formula: `f(n) = max(minimum, g(n))` where `g(n)` is the base strategy
  ///
  /// This modifier ensures that no delay returned by the strategy is less than
  /// the specified minimum duration.
  ///
  /// - Parameter minimum: The minimum duration to enforce.
  /// - Returns: A backoff strategy that never returns delays shorter than the minimum.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var backoff = Backoff
  ///   .exponential(factor: 2, initial: .milliseconds(100))
  ///   .minimum(.milliseconds(200))
  /// backoff.nextDuration() // 200ms (enforced minimum)
  /// ```
  @inlinable public func minimum(_ minimum: Duration) -> some BackoffStrategy<Duration> {
    return MinimumBackoffStrategy(base: self, minimum: minimum)
  }

  /// Applies a maximum duration constraint to this backoff strategy.
  ///
  /// Formula: `f(n) = min(maximum, g(n))` where `g(n)` is the base strategy
  ///
  /// This modifier ensures that no delay returned by the strategy exceeds
  /// the specified maximum duration, effectively capping exponential growth.
  ///
  /// - Parameter maximum: The maximum duration to enforce.
  /// - Returns: A backoff strategy that never returns delays longer than the maximum.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var backoff = Backoff
  ///   .exponential(factor: 2, initial: .milliseconds(100))
  ///   .maximum(.seconds(5))
  /// // Delays will cap at 5 seconds instead of growing indefinitely
  /// ```
  @inlinable public func maximum(_ maximum: Duration) -> some BackoffStrategy<Duration> {
    return MaximumBackoffStrategy(base: self, maximum: maximum)
  }
}

@available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension BackoffStrategy where Duration == Swift.Duration {
  /// Applies full jitter to this backoff strategy.
  ///
  /// Formula: `f(n) = random(0, g(n))` where `g(n)` is the base strategy
  ///
  /// Jitter prevents the thundering herd problem where multiple clients retry
  /// simultaneously, reducing server load spikes and improving system stability.
  ///
  /// - Parameter generator: The random number generator to use. Defaults to `SystemRandomNumberGenerator()`.
  /// - Returns: A backoff strategy with full jitter applied.
  @inlinable public func fullJitter<RNG: RandomNumberGenerator>(using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration> {
    return FullJitterBackoffStrategy(base: self, generator: generator)
  }

  /// Applies equal jitter to this backoff strategy.
  ///
  /// Formula: `f(n) = random(g(n) / 2, g(n))` where `g(n)` is the base strategy
  ///
  /// Jitter prevents the thundering herd problem where multiple clients retry
  /// simultaneously, reducing server load spikes and improving system stability.
  ///
  /// - Parameter generator: The random number generator to use. Defaults to `SystemRandomNumberGenerator()`.
  /// - Returns: A backoff strategy with equal jitter applied.
  @inlinable public func equalJitter<RNG: RandomNumberGenerator>(using generator: RNG = SystemRandomNumberGenerator()) -> some BackoffStrategy<Duration> {
    return EqualJitterBackoffStrategy(base: self, generator: generator)
  }
}
#endif

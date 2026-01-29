#if compiler(>=6.2)
/// A protocol for defining backoff strategies that generate delays between retry attempts.
///
/// A `BackoffStrategy` represents an immutable configuration for generating delay durations.
/// To produce actual delay values, call `makeIterator()` to create a `BackoffIterator`.
/// This separation allows strategies to be `Sendable` and reusable, while iterators manage
/// the mutable state for generating successive delays.
///
/// ## Example
///
/// ```swift
/// let strategy = Backoff.exponential(factor: 2, initial: .milliseconds(100))
/// var iterator = strategy.makeIterator()
/// iterator.nextDuration() // 100ms
/// iterator.nextDuration() // 200ms
/// iterator.nextDuration() // 400ms
/// ```
@available(AsyncAlgorithms 1.1, *)
public protocol BackoffStrategy<Duration> {
  associatedtype Iterator: BackoffIterator
  associatedtype Duration: DurationProtocol where Duration == Iterator.Duration
  func makeIterator() -> Iterator
}

/// A protocol for stateful iteration over backoff delay durations.
///
/// A `BackoffIterator` is created from a `BackoffStrategy` via `makeIterator()`.
/// Each call to `nextDuration()` returns the delay for the next retry attempt.
/// Iterators are stateful; they may track the number of invocations or the
/// previously returned duration to calculate the next delay.
@available(AsyncAlgorithms 1.1, *)
public protocol BackoffIterator {
  associatedtype Duration: DurationProtocol
  mutating func nextDuration() -> Duration
  mutating func nextDuration(using generator: inout some RandomNumberGenerator) -> Duration
}

@available(AsyncAlgorithms 1.1, *)
extension BackoffIterator {
  /// Default implementation that ignores the random number generator and
  /// calls ``nextDuration()``.
  ///
  /// Override this method in iterators that use randomization (such as jitter)
  /// to use the provided generator instead of the system default.
  public mutating func nextDuration(using generator: inout some RandomNumberGenerator) -> Duration {
    nextDuration()
  }
}

@available(AsyncAlgorithms 1.1, *)
@usableFromInline struct ConstantBackoffStrategy<Duration: DurationProtocol>: BackoffStrategy, Sendable {
  @usableFromInline let constant: Duration
  @usableFromInline init(constant: Duration) {
    precondition(constant >= .zero, "Constant must be greater than or equal to 0")
    self.constant = constant
  }
  @inlinable func makeIterator() -> Iterator {
    return Iterator(constant: constant)
  }
  @usableFromInline struct Iterator: BackoffIterator {
    @usableFromInline let constant: Duration
    @usableFromInline init(constant: Duration) {
      self.constant = constant
    }
    @inlinable @inline(__always) func nextDuration() -> Duration {
      return constant
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
@usableFromInline struct LinearBackoffStrategy: BackoffStrategy, Sendable {
  @usableFromInline let initial: Duration
  @usableFromInline let increment: Duration
  @usableFromInline init(increment: Duration, initial: Duration) {
    precondition(initial >= .zero, "Initial must be greater than or equal to 0")
    precondition(increment >= .zero, "Increment must be greater than or equal to 0")
    self.initial = initial
    self.increment = increment
  }
  @inlinable func makeIterator() -> Iterator {
    return Iterator(current: initial, increment: increment)
  }
  @usableFromInline struct Iterator: BackoffIterator {
    @usableFromInline var current: Duration
    @usableFromInline let increment: Duration
    @usableFromInline var hasOverflown = false
    @usableFromInline init(current: Duration, increment: Duration) {
      self.current = current
      self.increment = increment
    }
    @inlinable @inline(__always) mutating func nextDuration() -> Duration {
      if hasOverflown {
        return Duration(attoseconds: .max)
      } else {
        let (next, hasOverflown) = current.attoseconds.addingReportingOverflow(increment.attoseconds)
        if hasOverflown {
          self.hasOverflown = true
          return Duration(attoseconds: .max)
        } else {
          defer { current = Duration(attoseconds: next) }
          return current
        }
      }
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
@usableFromInline struct ExponentialBackoffStrategy: BackoffStrategy, Sendable {
  @usableFromInline let initial: Duration
  @usableFromInline let factor: Int128
  @usableFromInline init(factor: Int128, initial: Duration) {
    precondition(initial >= .zero, "Initial must be greater than or equal to 0")
    precondition(factor >= 1, "Factor must be greater than or equal to 1")
    self.initial = initial
    self.factor = factor
  }
  @inlinable func makeIterator() -> Iterator {
    return Iterator(current: initial, factor: factor)
  }
  @usableFromInline struct Iterator: BackoffIterator {
    @usableFromInline var current: Duration
    @usableFromInline let factor: Int128
    @usableFromInline var hasOverflown = false
    @usableFromInline init(current: Duration, factor: Int128) {
      self.current = current
      self.factor = factor
    }
    @inlinable @inline(__always) mutating func nextDuration() -> Duration {
      if hasOverflown {
        return Duration(attoseconds: .max)
      } else {
        let (next, hasOverflown) = current.attoseconds.multipliedReportingOverflow(by: factor)
        if hasOverflown {
          self.hasOverflown = true
          return Duration(attoseconds: .max)
        } else {
          defer { current = Duration(attoseconds: next) }
          return current
        }
      }
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
@usableFromInline struct MinimumBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy {
  @usableFromInline let base: Base
  @usableFromInline let minimum: Base.Duration
  @usableFromInline init(base: Base, minimum: Base.Duration) {
    self.base = base
    self.minimum = minimum
  }
  @inlinable public func makeIterator() -> Iterator {
    return Iterator(base: base.makeIterator(), minimum: minimum)
  }
  @usableFromInline struct Iterator: BackoffIterator {
    @usableFromInline var base: Base.Iterator
    @usableFromInline let minimum: Base.Duration
    @usableFromInline init(base: Base.Iterator, minimum: Base.Duration) {
      self.base = base
      self.minimum = minimum
    }
    @inlinable @inline(__always) mutating func nextDuration() -> Base.Duration {
      return max(minimum, base.nextDuration())
    }
    @inlinable @inline(__always) mutating func nextDuration(using generator: inout some RandomNumberGenerator) -> Base.Duration {
      return max(minimum, base.nextDuration(using: &generator))
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
extension MinimumBackoffStrategy: Sendable where Base: Sendable {}

@available(AsyncAlgorithms 1.1, *)
@usableFromInline struct MaximumBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy {
  @usableFromInline let base: Base
  @usableFromInline let maximum: Base.Duration
  @usableFromInline init(base: Base, maximum: Base.Duration) {
    self.base = base
    self.maximum = maximum
  }
  @inlinable func makeIterator() -> Iterator {
    return Iterator(base: base.makeIterator(), maximum: maximum)
  }
  @usableFromInline struct Iterator: BackoffIterator {
    @usableFromInline var base: Base.Iterator
    @usableFromInline let maximum: Base.Duration
    @usableFromInline init(base: Base.Iterator, maximum: Base.Duration) {
      self.base = base
      self.maximum = maximum
    }
    @inlinable @inline(__always) mutating func nextDuration() -> Base.Duration {
      return min(maximum, base.nextDuration())
    }
    @inlinable @inline(__always) mutating func nextDuration(using generator: inout some RandomNumberGenerator) -> Base.Duration {
      return min(maximum, base.nextDuration(using: &generator))
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
extension MaximumBackoffStrategy: Sendable where Base: Sendable {}

@available(AsyncAlgorithms 1.1, *)
@usableFromInline struct FullJitterBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy where Base.Duration == Swift.Duration {
  @usableFromInline let base: Base
  @usableFromInline init(base: Base) {
    self.base = base
  }
  @inlinable func makeIterator() -> Iterator {
    return Iterator(base: base.makeIterator())
  }
  @usableFromInline struct Iterator: BackoffIterator {
    @usableFromInline var base: Base.Iterator
    @usableFromInline init(base: Base.Iterator) {
      self.base = base
    }
    @inlinable @inline(__always) mutating func nextDuration() -> Base.Duration {
      return .init(attoseconds: Int128.random(in: 0...base.nextDuration().attoseconds))
    }
    @inlinable @inline(__always) mutating func nextDuration(using generator: inout some RandomNumberGenerator) -> Base.Duration {
      return .init(attoseconds: Int128.random(in: 0...base.nextDuration(using: &generator).attoseconds, using: &generator))
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
extension FullJitterBackoffStrategy: Sendable where Base: Sendable {}

@available(AsyncAlgorithms 1.1, *)
@usableFromInline struct EqualJitterBackoffStrategy<Base: BackoffStrategy>: BackoffStrategy where Base.Duration == Swift.Duration {
  @usableFromInline let base: Base
  @usableFromInline init(base: Base) {
    self.base = base
  }
  @inlinable func makeIterator() -> Iterator {
    return Iterator(base: base.makeIterator())
  }
  @usableFromInline struct Iterator: BackoffIterator {
    @usableFromInline var base: Base.Iterator
    @usableFromInline init(base: Base.Iterator) {
      self.base = base
    }
    @inlinable @inline(__always) mutating func nextDuration() -> Base.Duration {
      let duration = base.nextDuration().attoseconds
      return .init(attoseconds: Int128.random(in: (duration / 2)...duration))
    }
    @inlinable @inline(__always) mutating func nextDuration(using generator: inout some RandomNumberGenerator) -> Duration {
      let duration = base.nextDuration(using: &generator).attoseconds
      return .init(attoseconds: Int128.random(in: (duration / 2)...duration, using: &generator))
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
extension EqualJitterBackoffStrategy: Sendable where Base: Sendable {}

@available(AsyncAlgorithms 1.1, *)
public enum Backoff {
  /// Creates a constant backoff strategy that always returns the same delay.
  ///
  /// Formula: `f(n) = constant`
  ///
  /// - Precondition: `constant` must be greater than or equal to zero.
  ///
  /// - Parameter constant: The fixed duration to wait between retry attempts.
  /// - Returns: A backoff strategy that always returns the constant duration.
  @inlinable public static func constant<Duration: DurationProtocol>(
    _ constant: Duration
  ) -> some BackoffStrategy<Duration> & Sendable {
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
  /// let backoff = Backoff.constant(.milliseconds(100))
  /// var iterator = backoff.makeIterator()
  /// iterator.nextDuration() // 100ms
  /// iterator.nextDuration() // 100ms
  /// ```
  @inlinable public static func constant(
    _ constant: Duration
  ) -> some BackoffStrategy<Duration> & Sendable {
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
  ///
  /// - Note: If the computed duration overflows, subsequent calls return the maximum
  ///   representable duration (`Duration(attoseconds: .max)`).
  ///
  /// ## Example
  ///
  /// ```swift
  /// let backoff = Backoff.linear(increment: .milliseconds(100), initial: .milliseconds(100))
  /// var iterator = backoff.makeIterator()
  /// iterator.nextDuration() // 100ms
  /// iterator.nextDuration() // 200ms
  /// iterator.nextDuration() // 300ms
  /// ```
  @inlinable public static func linear(
    increment: Duration,
    initial: Duration
  ) -> some BackoffStrategy<Duration> & Sendable {
    return LinearBackoffStrategy(increment: increment, initial: initial)
  }

  /// Creates an exponential backoff strategy where delays grow exponentially.
  ///
  /// Formula: `f(n) = initial * factor^n`
  ///
  /// - Precondition: `initial` must be greater than or equal to zero.
  /// - Precondition: `factor` must be greater than or equal to 1.
  ///
  /// - Parameters:
  ///   - factor: The multiplication factor for each retry attempt.
  ///   - initial: The initial delay for the first retry attempt.
  /// - Returns: A backoff strategy with exponentially increasing delays.
  ///
  /// - Note: If the computed duration overflows, subsequent calls return the maximum
  ///   representable duration (`Duration(attoseconds: .max)`).
  ///
  /// ## Example
  ///
  /// ```swift
  /// let backoff = Backoff.exponential(factor: 2, initial: .milliseconds(100))
  /// var iterator = backoff.makeIterator()
  /// iterator.nextDuration() // 100ms
  /// iterator.nextDuration() // 200ms
  /// iterator.nextDuration() // 400ms
  /// ```
  @inlinable public static func exponential(
    factor: Int128,
    initial: Duration
  ) -> some BackoffStrategy<Duration> & Sendable {
    return ExponentialBackoffStrategy(factor: factor, initial: initial)
  }
}

@available(AsyncAlgorithms 1.1, *)
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
  /// let backoff = Backoff
  ///   .exponential(factor: 2, initial: .milliseconds(100))
  ///   .minimum(.milliseconds(200))
  /// var iterator = backoff.makeIterator()
  /// iterator.nextDuration() // 200ms (enforced minimum)
  /// ```
  @inlinable public func minimum(
    _ minimum: Duration
  ) -> some BackoffStrategy<Duration> {
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
  /// let backoff = Backoff
  ///   .exponential(factor: 2, initial: .milliseconds(100))
  ///   .maximum(.seconds(5))
  /// var iterator = backoff.makeIterator()
  /// // Delays will cap at 5 seconds instead of growing indefinitely
  /// ```
  @inlinable public func maximum(
    _ maximum: Duration
  ) -> some BackoffStrategy<Duration> {
    return MaximumBackoffStrategy(base: self, maximum: maximum)
  }

  /// Applies full jitter to this backoff strategy.
  ///
  /// Formula: `f(n) = random(0, g(n))` where `g(n)` is the base strategy
  ///
  /// Jitter prevents the thundering herd problem where multiple clients retry
  /// simultaneously, reducing server load spikes and improving system stability.
  ///
  /// - Returns: A backoff strategy with full jitter applied.
  @inlinable public func fullJitter() -> some BackoffStrategy<Duration> where Duration == Swift.Duration {
    return FullJitterBackoffStrategy(base: self)
  }

  /// Applies equal jitter to this backoff strategy.
  ///
  /// Formula: `f(n) = random(g(n)/2, g(n))` where `g(n)` is the base strategy
  ///
  /// Equal jitter provides a balance between full jitter and no jitter, ensuring
  /// at least half of the computed delay is always applied while still providing
  /// randomization to prevent thundering herd.
  ///
  /// - Returns: A backoff strategy with equal jitter applied.
  @inlinable public func equalJitter() -> some BackoffStrategy<Duration> where Duration == Swift.Duration {
    return EqualJitterBackoffStrategy(base: self)
  }
}

@available(AsyncAlgorithms 1.1, *)
extension BackoffStrategy where Self: Sendable {
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
  /// let backoff = Backoff
  ///   .exponential(factor: 2, initial: .milliseconds(100))
  ///   .minimum(.milliseconds(200))
  /// var iterator = backoff.makeIterator()
  /// iterator.nextDuration() // 200ms (enforced minimum)
  /// ```
  @inlinable public func minimum(
    _ minimum: Duration
  ) -> some BackoffStrategy<Duration> & Sendable {
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
  /// let backoff = Backoff
  ///   .exponential(factor: 2, initial: .milliseconds(100))
  ///   .maximum(.seconds(5))
  /// var iterator = backoff.makeIterator()
  /// // Delays will cap at 5 seconds instead of growing indefinitely
  /// ```
  @inlinable public func maximum(
    _ maximum: Duration
  ) -> some BackoffStrategy<Duration> & Sendable {
    return MaximumBackoffStrategy(base: self, maximum: maximum)
  }

  /// Applies full jitter to this backoff strategy.
  ///
  /// Formula: `f(n) = random(0, g(n))` where `g(n)` is the base strategy
  ///
  /// Jitter prevents the thundering herd problem where multiple clients retry
  /// simultaneously, reducing server load spikes and improving system stability.
  ///
  /// - Returns: A backoff strategy with full jitter applied.
  @inlinable public func fullJitter() -> some BackoffStrategy<Duration> & Sendable where Duration == Swift.Duration {
    return FullJitterBackoffStrategy(base: self)
  }

  /// Applies equal jitter to this backoff strategy.
  ///
  /// Formula: `f(n) = random(g(n)/2, g(n))` where `g(n)` is the base strategy
  ///
  /// Equal jitter provides a balance between full jitter and no jitter, ensuring
  /// at least half of the computed delay is always applied while still providing
  /// randomization to prevent thundering herd.
  ///
  /// - Returns: A backoff strategy with equal jitter applied.
  @inlinable public func equalJitter() -> some BackoffStrategy<Duration> & Sendable where Duration == Swift.Duration {
    return EqualJitterBackoffStrategy(base: self)
  }
}
#endif

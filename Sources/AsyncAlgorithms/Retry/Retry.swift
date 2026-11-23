#if compiler(>=6.2)
@available(AsyncAlgorithms 1.1, *)
public struct RetryAction<Duration: DurationProtocol> {
  @usableFromInline enum Action {
    case backoff(Duration)
    case stop
  }
  @usableFromInline let action: Action
  @usableFromInline init(action: Action) {
    self.action = action
  }

  /// Indicates that retrying should stop immediately and the error should be rethrown.
  @inlinable public static var stop: Self {
    return .init(action: .stop)
  }

  /// Indicates that retrying should continue after waiting for the specified duration.
  ///
  /// - Parameter duration: The duration to wait before the next retry attempt.
  @inlinable public static func backoff(_ duration: Duration) -> Self {
    return .init(action: .backoff(duration))
  }
}

/// Executes an asynchronous operation with retry logic and customizable backoff strategies.
///
/// This function executes an asynchronous operation up to a specified number of attempts,
/// with customizable delays and error-based retry decisions between attempts.
///
/// The retry logic follows this sequence:
/// 1. Execute the operation
/// 2. If successful, return the result
/// 3. If failed and this was not the final attempt:
///    - Call the strategy closure with the error
///      - If the strategy returns `.stop`, rethrow the error immediately
///      - If the strategy returns `.backoff`, suspend for the given duration
///      - Return to step 1
/// 4. If failed on the final attempt, rethrow the error without consulting the strategy
///
/// Given this sequence, there are four termination conditions (when retrying will be stopped):
/// - The operation completes without throwing an error
/// - The operation has been attempted `maxAttempts` times
/// - The strategy closure returns `.stop`
/// - The clock throws
///
/// ## Cancellation
///
/// `retry` does not introduce special cancellation handling. If your code cooperatively
/// cancels by throwing, ensure your strategy returns `.stop` for that error. Otherwise,
/// retries continue unless the used clock throws on cancellation.
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - tolerance: The tolerance for the sleep operation between retries. This value is passed
///                to `clock.sleep(for:tolerance:)` and allows the system scheduling flexibility.
///   - clock: The clock to use for timing delays between retries.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines the retry action based on the error.
///                Defaults to immediate retry with no delay.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if the strategy returns `.stop`.
///
/// ## Example
///
/// This example honors a server-provided backoff duration from the error:
///
/// ```swift
/// let result = try await retry(maxAttempts: 5, clock: ContinuousClock()) {
///   try await someHTTPOperation()
/// } strategy: { error in
///   if let error = error as? StatusCodeError {
///     return .backoff(.seconds(error.retryAfter))
///   }
///   return .stop
/// }
/// ```
@available(AsyncAlgorithms 1.1, *)
@inlinable nonisolated(nonsending) public func retry<Result, ErrorType, DurationType>(
  maxAttempts: Int,
  tolerance: DurationType? = nil,
  clock: any Clock<DurationType>,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> RetryAction<DurationType> = { _ in .backoff(.zero) }
) async throws -> Result where DurationType: DurationProtocol, ErrorType: Error {
  precondition(maxAttempts > 0, "Must have at least one attempt")
  for _ in 0..<maxAttempts - 1 {
    do {
      return try await operation()
    } catch {
      switch strategy(error).action {
      case .backoff(let duration):
        try await clock.sleep(for: duration, tolerance: tolerance)
      case .stop:
        throw error
      }
    }
  }
  return try await operation()
}

/// Executes an asynchronous operation with retry logic and customizable backoff strategies.
///
/// This function executes an asynchronous operation up to a specified number of attempts,
/// with customizable delays and error-based retry decisions between attempts.
///
/// The retry logic follows this sequence:
/// 1. Execute the operation
/// 2. If successful, return the result
/// 3. If failed and this was not the final attempt:
///    - Call the strategy closure with the error
///      - If the strategy returns `.stop`, rethrow the error immediately
///      - If the strategy returns `.backoff`, suspend for the given duration
///      - Return to step 1
/// 4. If failed on the final attempt, rethrow the error without consulting the strategy
///
/// Given this sequence, there are four termination conditions (when retrying will be stopped):
/// - The operation completes without throwing an error
/// - The operation has been attempted `maxAttempts` times
/// - The strategy closure returns `.stop`
/// - The clock throws
///
/// ## Cancellation
///
/// `retry` does not introduce special cancellation handling. If your code cooperatively
/// cancels by throwing, ensure your strategy returns `.stop` for that error. Otherwise,
/// retries continue unless the used clock throws on cancellation.
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - tolerance: The tolerance for the sleep operation between retries. This value is passed
///                to `clock.sleep(for:tolerance:)` and allows the system scheduling flexibility.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines the retry action based on the error.
///                Defaults to immediate retry with no delay.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if the strategy returns `.stop`.
///
/// ## Example
///
/// This example honors a server-provided backoff duration from the error:
///
/// ```swift
/// let result = try await retry(maxAttempts: 5) {
///   try await someHTTPOperation()
/// } strategy: { error in
///   if let error = error as? StatusCodeError {
///     return .backoff(.seconds(error.retryAfter))
///   }
///   return .stop
/// }
/// ```
@available(AsyncAlgorithms 1.1, *)
@inlinable nonisolated(nonsending) public func retry<Result, ErrorType>(
  maxAttempts: Int,
  tolerance: ContinuousClock.Duration? = nil,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> RetryAction<ContinuousClock.Duration> = { _ in .backoff(.zero) }
) async throws -> Result where ErrorType: Error {
  return try await retry(
    maxAttempts: maxAttempts,
    tolerance: tolerance,
    clock: ContinuousClock(),
    operation: operation,
    strategy: strategy
  )
}

/// Executes an asynchronous operation with retry logic using a backoff strategy.
///
/// This function executes an asynchronous operation up to a specified number of attempts.
/// When the operation fails, the backoff strategy determines how long to wait before
/// the next attempt. Common strategies include exponential backoff with jitter to
/// prevent thundering herd problems.
///
/// The retry logic follows this sequence:
/// 1. Execute the operation
/// 2. If successful, return the result
/// 3. If failed and this was not the final attempt:
///    - Call the `strategy` closure with the error
///      - If `strategy` returns `false`, rethrow the error immediately
///      - If `strategy` returns `true`, suspend for the next backoff duration
///      - Return to step 1
/// 4. If failed on the final attempt, rethrow the error without consulting `strategy`
///
/// Given this sequence, there are four termination conditions (when retrying will be stopped):
/// - The operation completes without throwing an error
/// - The operation has been attempted `maxAttempts` times
/// - The `strategy` closure returns `false`
/// - The clock throws
///
/// ## Cancellation
///
/// `retry` does not introduce special cancellation handling. If your code cooperatively
/// cancels by throwing, ensure `strategy` returns `false` for that error. Otherwise,
/// retries continue unless the used clock throws on cancellation.
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - backoff: The backoff strategy to use for delays between retries.
///   - tolerance: The tolerance for the sleep operation between retries. This value is passed
///                to `clock.sleep(for:tolerance:)` and allows the system scheduling flexibility.
///   - clock: The clock to use for timing delays between retries.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines whether to retry based on the error.
///               Return `true` to retry with backoff, `false` to stop immediately.
///               Defaults to always retrying.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if `strategy` returns `false`.
///
/// ## Example
///
/// ```swift
/// let backoff = Backoff
///   .exponential(factor: 2, initial: .milliseconds(100))
///   .maximum(.seconds(10))
///   .fullJitter()
///
/// let result = try await retry(maxAttempts: 5, backoff: backoff) {
///   try await someHTTPOperation()
/// }
/// ```
@available(AsyncAlgorithms 1.1, *)
@inlinable nonisolated(nonsending) public func retry<Result, ErrorType, DurationType, Strategy>(
  maxAttempts: Int,
  backoff: Strategy,
  tolerance: DurationType? = nil,
  clock: any Clock<DurationType>,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> Bool = { _ in true }
) async throws -> Result where DurationType: DurationProtocol, ErrorType: Error, Strategy: BackoffStrategy<DurationType> {
  var iterator = backoff.makeIterator()
  return try await retry(
    maxAttempts: maxAttempts,
    tolerance: tolerance,
    clock: clock,
    operation: operation,
    strategy: { error in
      if strategy(error) {
        return .backoff(iterator.nextDuration())
      } else {
        return .stop
      }
    }
  )
}

/// Executes an asynchronous operation with retry logic using a backoff strategy.
///
/// This function executes an asynchronous operation up to a specified number of attempts.
/// When the operation fails, the backoff strategy determines how long to wait before
/// the next attempt. Common strategies include exponential backoff with jitter to
/// prevent thundering herd problems.
///
/// The retry logic follows this sequence:
/// 1. Execute the operation
/// 2. If successful, return the result
/// 3. If failed and this was not the final attempt:
///    - Call the `strategy` closure with the error
///      - If `strategy` returns `false`, rethrow the error immediately
///      - If `strategy` returns `true`, suspend for the next backoff duration
///      - Return to step 1
/// 4. If failed on the final attempt, rethrow the error without consulting `strategy`
///
/// Given this sequence, there are four termination conditions (when retrying will be stopped):
/// - The operation completes without throwing an error
/// - The operation has been attempted `maxAttempts` times
/// - The `strategy` closure returns `false`
/// - The clock throws
///
/// ## Cancellation
///
/// `retry` does not introduce special cancellation handling. If your code cooperatively
/// cancels by throwing, ensure `strategy` returns `false` for that error. Otherwise,
/// retries continue unless the used clock throws on cancellation.
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - backoff: The backoff strategy to use for delays between retries.
///   - tolerance: The tolerance for the sleep operation between retries. This value is passed
///                to `clock.sleep(for:tolerance:)` and allows the system scheduling flexibility.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines whether to retry based on the error.
///               Return `true` to retry with backoff, `false` to stop immediately.
///               Defaults to always retrying.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if `strategy` returns `false`.
///
/// ## Example
///
/// ```swift
/// let backoff = Backoff
///   .exponential(factor: 2, initial: .milliseconds(100))
///   .maximum(.seconds(10))
///   .fullJitter()
///
/// let result = try await retry(maxAttempts: 5, backoff: backoff) {
///   try await someHTTPOperation()
/// }
/// ```
@available(AsyncAlgorithms 1.1, *)
@inlinable nonisolated(nonsending) public func retry<Result, ErrorType, Strategy>(
  maxAttempts: Int,
  backoff: Strategy,
  tolerance: ContinuousClock.Duration? = nil,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> Bool = { _ in true }
) async throws -> Result where ErrorType: Error, Strategy: BackoffStrategy<ContinuousClock.Duration> {
  return try await retry(
    maxAttempts: maxAttempts,
    backoff: backoff,
    tolerance: tolerance,
    clock: ContinuousClock(),
    operation: operation,
    strategy: strategy
  )
}

/// Executes an asynchronous operation with retry logic using a backoff strategy and a
/// custom random number generator.
///
/// This overload forwards the provided random number generator to the backoff iterator
/// via ``BackoffIterator/nextDuration(using:)``, allowing callers to control the source
/// of randomness used by jitter strategies.
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - backoff: The backoff strategy to use for delays between retries.
///   - generator: The random number generator to use for jitter.
///   - tolerance: The tolerance for the sleep operation between retries. This value is passed
///                to `clock.sleep(for:tolerance:)` and allows the system scheduling flexibility.
///   - clock: The clock to use for timing delays between retries.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines whether to retry based on the error.
///               Return `true` to retry with backoff, `false` to stop immediately.
///               Defaults to always retrying.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if `strategy` returns `false`.
@available(AsyncAlgorithms 1.1, *)
@inlinable nonisolated(nonsending) public func retry<Result, ErrorType, DurationType, Strategy>(
  maxAttempts: Int,
  backoff: Strategy,
  using generator: inout some RandomNumberGenerator,
  tolerance: DurationType? = nil,
  clock: any Clock<DurationType>,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> Bool = { _ in true }
) async throws -> Result where DurationType: DurationProtocol, ErrorType: Error, Strategy: BackoffStrategy<DurationType> {
  var iterator = backoff.makeIterator()
  return try await retry(
    maxAttempts: maxAttempts,
    tolerance: tolerance,
    clock: clock,
    operation: operation,
    strategy: { error in
      if strategy(error) {
        return .backoff(iterator.nextDuration(using: &generator))
      } else {
        return .stop
      }
    }
  )
}

/// Executes an asynchronous operation with retry logic using a backoff strategy and a
/// custom random number generator, using `ContinuousClock` for timing.
///
/// This is a convenience overload that uses `ContinuousClock` as the clock.
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - backoff: The backoff strategy to use for delays between retries.
///   - generator: The random number generator to use for jitter.
///   - tolerance: The tolerance for the sleep operation between retries. This value is passed
///                to `clock.sleep(for:tolerance:)` and allows the system scheduling flexibility.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines whether to retry based on the error.
///               Return `true` to retry with backoff, `false` to stop immediately.
///               Defaults to always retrying.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if `strategy` returns `false`.
@available(AsyncAlgorithms 1.1, *)
@inlinable nonisolated(nonsending) public func retry<Result, ErrorType, Strategy>(
  maxAttempts: Int,
  backoff: Strategy,
  using generator: inout some RandomNumberGenerator,
  tolerance: ContinuousClock.Duration? = nil,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> Bool = { _ in true }
) async throws -> Result where ErrorType: Error, Strategy: BackoffStrategy<ContinuousClock.Duration> {
  return try await retry(
    maxAttempts: maxAttempts,
    backoff: backoff,
    using: &generator,
    tolerance: tolerance,
    clock: ContinuousClock(),
    operation: operation,
    strategy: strategy
  )
}
#endif

#if compiler(>=6.2)
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
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
/// retries continue unless the clock throws on cancellation (which, at the time of writing,
/// both `ContinuousClock` and `SuspendingClock` do).
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - tolerance: The tolerance for the sleep operation between retries.
///   - clock: The clock to use for timing delays between retries.
///   - isolation: The actor isolation to maintain during execution.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines the retry action based on the error.
///                Defaults to immediate retry with no delay.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if the strategy returns `.stop`.
///
/// ## Example
///
/// ```swift
/// var backoff = Backoff.exponential(factor: 2, initial: .milliseconds(100))
/// let result = try await retry(maxAttempts: 3, clock: ContinuousClock()) {
///   try await someNetworkOperation()
/// } strategy: { error in
///   return .backoff(backoff.nextDuration())
/// }
/// ```
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@inlinable public func retry<Result, ErrorType, ClockType>(
  maxAttempts: Int,
  tolerance: ClockType.Instant.Duration? = nil,
  clock: ClockType,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> RetryAction<ClockType.Instant.Duration> = { _ in .backoff(.zero) }
) async throws -> Result where ClockType: Clock, ErrorType: Error {
  precondition(maxAttempts > 0, "Must have at least one attempt")
  for _ in 0..<maxAttempts - 1 {
    do {
      return try await operation()
    } catch {
      switch strategy(error).action {
      case .backoff(let duration):
        let deadline = clock.now.advanced(by: duration)
        try await Task.sleep(until: deadline, tolerance: tolerance, clock: clock)
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
/// retries continue unless the clock throws on cancellation (which, at the time of writing,
/// both `ContinuousClock` and `SuspendingClock` do).
///
/// - Precondition: `maxAttempts` must be greater than 0.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to make.
///   - tolerance: The tolerance for the sleep operation between retries.
///   - isolation: The actor isolation to maintain during execution.
///   - operation: The asynchronous operation to retry.
///   - strategy: A closure that determines the retry action based on the error.
///                Defaults to immediate retry with no delay.
/// - Returns: The result of the successful operation.
/// - Throws: The error from the operation if all retry attempts fail or if the strategy returns `.stop`.
///
/// ## Example
///
/// ```swift
/// var backoff = Backoff.exponential(factor: 2, initial: .milliseconds(100))
/// let result = try await retry(maxAttempts: 3) {
///   try await someNetworkOperation()
/// } strategy: { error in
///   return .backoff(backoff.nextDuration())
/// }
/// ```
@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@inlinable public func retry<Result, ErrorType>(
  maxAttempts: Int,
  tolerance: ContinuousClock.Instant.Duration? = nil,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(ErrorType) -> Result,
  strategy: (ErrorType) -> RetryAction<ContinuousClock.Instant.Duration> = { _ in .backoff(.zero) }
) async throws -> Result where ErrorType: Error {
  return try await retry(
    maxAttempts: maxAttempts,
    tolerance: tolerance,
    clock: ContinuousClock(),
    operation: operation,
    strategy: strategy
  )
}
#endif

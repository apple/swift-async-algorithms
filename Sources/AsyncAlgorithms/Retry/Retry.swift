@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public enum RetryStrategy<Duration: DurationProtocol> {
  case backoff(Duration)
  case stop
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@inlinable
public func retry<Result, ErrorType, ClockType>(
  maxAttempts: Int = 3,
  tolerance: ClockType.Instant.Duration? = nil,
  clock: ClockType,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(ErrorType) -> sending Result,
  strategy: (_ attempt: Int, ErrorType) -> RetryStrategy<ClockType.Instant.Duration> = { _, _ in .backoff(.zero) }
) async throws -> Result where ClockType: Clock, ErrorType: Error {
  precondition(maxAttempts > 0, "Must have at least one attempt")
  for attempt in 0..<maxAttempts - 1 {
    do {
      return try await operation()
    } catch where Task.isCancelled {
      throw error
    } catch {
      switch strategy(attempt, error) {
      case .backoff(let duration):
        try await Task.sleep(for: duration, tolerance: tolerance, clock: clock)
      case .stop:
        throw error
      }
    }
  }
  return try await operation()
}

@available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
@inlinable
public func retry<Result, ErrorType>(
  maxAttempts: Int = 3,
  tolerance: ContinuousClock.Instant.Duration? = nil,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(ErrorType) -> sending Result,
  strategy: (_ attempt: Int, ErrorType) -> RetryStrategy<ContinuousClock.Instant.Duration> = { _, _ in .backoff(.zero) }
) async throws -> Result where ErrorType: Error {
  return try await retry(
    maxAttempts: maxAttempts,
    tolerance: tolerance,
    clock: ContinuousClock(),
    operation: operation,
    strategy: strategy
  )
}

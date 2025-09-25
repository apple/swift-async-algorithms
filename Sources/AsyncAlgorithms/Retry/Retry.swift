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
  @inlinable public static var stop: Self {
    return .init(action: .stop)
  }
  @inlinable public static func backoff(_ duration: Duration) -> Self {
    return .init(action: .backoff(duration))
  }
}

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

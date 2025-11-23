@testable import AsyncAlgorithms
import Testing

@Suite struct RetryTests {
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func singleAttempt() async throws {
    var operationAttempts = 0
    var strategyAttempts = 0
    await #expect(throws: Failure.self) {
      try await retry(maxAttempts: 1) {
        operationAttempts += 1
        throw Failure()
      } strategy: { _ in
        strategyAttempts += 1
        return .backoff(.zero)
      }
    }
    #expect(operationAttempts == 1)
    #expect(strategyAttempts == 0)
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func customCancellation() async throws {
    struct CustomCancellationError: Error {}
    let task = Task {
      try await retry(maxAttempts: 3) {
        if Task.isCancelled {
          throw CustomCancellationError()
        }
        throw Failure()
      } strategy: { error in
        if error is CustomCancellationError {
          return .stop
        } else {
          return .backoff(.zero)
        }
      }
    }
    task.cancel()
    await #expect(throws: CustomCancellationError.self) {
      try await task.value
    }
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func defaultCancellation() async throws {
    let task = Task {
      try await retry(maxAttempts: 3) {
        throw Failure()
      }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func successOnFirstAttempt() async throws {
    func doesNotActuallyThrow() throws { }
    var operationAttempts = 0
    var strategyAttempts = 0
    try await retry(maxAttempts: 3) {
      operationAttempts += 1
      try doesNotActuallyThrow()
    } strategy: { _ in
      strategyAttempts += 1
      return .backoff(.zero)
    }
    #expect(operationAttempts == 1)
    #expect(strategyAttempts == 0)
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func successOnSecondAttempt() async throws {
    var operationAttempts = 0
    var strategyAttempts = 0
    try await retry(maxAttempts: 3) {
      operationAttempts += 1
      if operationAttempts == 1 {
        throw Failure()
      }
    } strategy: { _ in
      strategyAttempts += 1
      return .backoff(.zero)
    }
    #expect(operationAttempts == 2)
    #expect(strategyAttempts == 1)
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func maxAttemptsExceeded() async throws {
    var operationAttempts = 0
    var strategyAttempts = 0
    await #expect(throws: Failure.self) {
      try await retry(maxAttempts: 3) {
        operationAttempts += 1
        throw Failure()
      } strategy: { _ in
        strategyAttempts += 1
        return .backoff(.zero)
      }
    }
    #expect(operationAttempts == 3)
    #expect(strategyAttempts == 2)
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func nonRetryableError() async throws {
    struct RetryableError: Error {}
    struct NonRetryableError: Error {}
    var operationAttempts = 0
    var strategyAttempts = 0
    await #expect(throws: NonRetryableError.self) {
      try await retry(maxAttempts: 5) {
        operationAttempts += 1
        if operationAttempts == 2 {
          throw NonRetryableError()
        }
        throw RetryableError()
      } strategy: { error in
        strategyAttempts += 1
        if error is NonRetryableError {
          return .stop
        }
        return .backoff(.zero)
      }
    }
    #expect(operationAttempts == 2)
    #expect(strategyAttempts == 2)
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @MainActor @Test func customClock() async throws {
    let clock = ManualClock()
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let operationAttempts = ManagedCriticalState(0)
    let task = Task { @MainActor in
      try await retry(maxAttempts: 3, clock: clock) {
        operationAttempts.withCriticalRegion { $0 += 1 }
        continuation.yield()
        throw Failure()
      } strategy: { _ in
        return .backoff(.steps(1))
      }
    }
    var iterator = stream.makeAsyncIterator()
    _ = await iterator.next()!
    #expect(operationAttempts.withCriticalRegion { $0 } == 1)
    clock.advance()
    _ = await iterator.next()!
    #expect(operationAttempts.withCriticalRegion { $0 } == 2)
    clock.advance()
    _ = await iterator.next()!
    #expect(operationAttempts.withCriticalRegion { $0 } == 3)
    await #expect(throws: Failure.self) {
      try await task.value
    }
  }
  
  #if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst)) || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Windows)
  @available(AsyncAlgorithms 1.1, *)
  @Test func zeroAttempts() async {
    await #expect(processExitsWith: .failure) {
      try await retry(maxAttempts: 0) { }
    }
  }
  #endif
}

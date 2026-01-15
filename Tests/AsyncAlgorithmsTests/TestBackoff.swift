import AsyncAlgorithms
import Testing

@Suite struct BackoffTests {
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func overflowSafety() {
    var strategy = Backoff.exponential(factor: 2, initial: .seconds(5)).maximum(.seconds(120))
    for _ in 0..<100 {
      _ = strategy.nextDuration()
    }
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func constantBackoff() {
    var strategy = Backoff.constant(.milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(5))
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func linearBackoff() {
    var strategy = Backoff.linear(increment: .milliseconds(2), initial: .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(3))
    #expect(strategy.nextDuration() == .milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(7))
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func exponentialBackoff() {
    var strategy = Backoff.exponential(factor: 2, initial: .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(2))
    #expect(strategy.nextDuration() == .milliseconds(4))
    #expect(strategy.nextDuration() == .milliseconds(8))
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func fullJitter() {
    var strategy = Backoff.constant(.milliseconds(100)).fullJitter(using: SplitMix64(seed: 42))
    #expect(strategy.nextDuration() == Duration(attoseconds: 15991039287692012)) // 15.99 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 34419071652363758)) // 34.41 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 86822807654653238)) // 86.82 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 80063187671350344)) // 80.06 ms
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func equalJitter() {
    var strategy = Backoff.constant(.milliseconds(100)).equalJitter(using: SplitMix64(seed: 42))
    #expect(strategy.nextDuration() == Duration(attoseconds: 57995519643846006)) // 57.99 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 67209535826181879)) // 67.20 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 93411403827326619)) // 93.41 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 90031593835675172)) // 90.03 ms
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func minimum() {
    var strategy = Backoff.exponential(factor: 2, initial: .milliseconds(1)).minimum(.milliseconds(2))
    #expect(strategy.nextDuration() == .milliseconds(2)) // 1 clamped to min 2
    #expect(strategy.nextDuration() == .milliseconds(2)) // 2 unchanged
    #expect(strategy.nextDuration() == .milliseconds(4)) // 4 unchanged
    #expect(strategy.nextDuration() == .milliseconds(8)) // 8 unchanged
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func maximum() {
    var strategy = Backoff.exponential(factor: 2, initial: .milliseconds(1)).maximum(.milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(1)) // 1 unchanged
    #expect(strategy.nextDuration() == .milliseconds(2)) // 2 unchanged
    #expect(strategy.nextDuration() == .milliseconds(4)) // 4 unchanged
    #expect(strategy.nextDuration() == .milliseconds(5)) // 8 unchanged clamped to max 5
  }
  
  #if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst)) || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Windows)
  @available(AsyncAlgorithms 1.1, *)
  @Test func constantPrecondition() async {
    await #expect(processExitsWith: .success) {
      _ = Backoff.constant(.milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.constant(.milliseconds(-1))
    }
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func linearPrecondition() async {
    await #expect(processExitsWith: .success) {
      _ = Backoff.linear(increment: .milliseconds(1), initial: .milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.linear(increment: .milliseconds(1), initial: .milliseconds(-1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.linear(increment: .milliseconds(-1), initial: .milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.linear(increment: .milliseconds(-1), initial: .milliseconds(-1))
    }
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func exponentialPrecondition() async {
    await #expect(processExitsWith: .success) {
      _ = Backoff.exponential(factor: 1, initial: .milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.exponential(factor: 1, initial: .milliseconds(-1))
    }
    await #expect(processExitsWith: .success) {
      _ = Backoff.exponential(factor: -1, initial: .milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.exponential(factor: -1, initial: .milliseconds(-1))
    }
  }
  #endif
}

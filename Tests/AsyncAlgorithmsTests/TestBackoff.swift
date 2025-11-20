import AsyncAlgorithms
import Testing

@Suite struct BackoffTests {
    
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
  @Test func constantBackoff() {
    var strategy = Backoff.constant(.milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(5))
  }
  
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
  @Test func linearBackoff() {
    var strategy = Backoff.linear(increment: .milliseconds(2), initial: .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(3))
    #expect(strategy.nextDuration() == .milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(7))
  }
  
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
  @Test func exponentialBackoff() {
    var strategy = Backoff.exponential(factor: 2, initial: .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(1))
    #expect(strategy.nextDuration() == .milliseconds(2))
    #expect(strategy.nextDuration() == .milliseconds(4))
    #expect(strategy.nextDuration() == .milliseconds(8))
  }
  
  @available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
  @Test func decorrelatedJitter() {
    var strategy = Backoff.decorrelatedJitter(factor: 3, base: .milliseconds(1), using: SplitMix64(seed: 43))
    #expect(strategy.nextDuration() == Duration(attoseconds: 2225543084173069)) // 2.22 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 5714816987299352)) // 5.71 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 2569829207199874)) // 2.56 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 6927552963135803)) // 6.92 ms
  }
  
  @available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
  @Test func fullJitter() {
    var strategy = Backoff.constant(.milliseconds(100)).fullJitter(using: SplitMix64(seed: 42))
    #expect(strategy.nextDuration() == Duration(attoseconds: 15991039287692012)) // 15.99 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 34419071652363758)) // 34.41 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 86822807654653238)) // 86.82 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 80063187671350344)) // 80.06 ms
  }
  
  @available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
  @Test func equalJitter() {
    var strategy = Backoff.constant(.milliseconds(100)).equalJitter(using: SplitMix64(seed: 42))
    #expect(strategy.nextDuration() == Duration(attoseconds: 57995519643846006)) // 57.99 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 67209535826181879)) // 67.20 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 93411403827326619)) // 93.41 ms
    #expect(strategy.nextDuration() == Duration(attoseconds: 90031593835675172)) // 90.03 ms
  }
  
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
  @Test func minimum() {
    var strategy = Backoff.exponential(factor: 2, initial: .milliseconds(1)).minimum(.milliseconds(2))
    #expect(strategy.nextDuration() == .milliseconds(2)) // 1 clamped to min 2
    #expect(strategy.nextDuration() == .milliseconds(2)) // 2 unchanged
    #expect(strategy.nextDuration() == .milliseconds(4)) // 4 unchanged
    #expect(strategy.nextDuration() == .milliseconds(8)) // 8 unchanged
  }
  
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
  @Test func maximum() {
    var strategy = Backoff.exponential(factor: 2, initial: .milliseconds(1)).maximum(.milliseconds(5))
    #expect(strategy.nextDuration() == .milliseconds(1)) // 1 unchanged
    #expect(strategy.nextDuration() == .milliseconds(2)) // 2 unchanged
    #expect(strategy.nextDuration() == .milliseconds(4)) // 4 unchanged
    #expect(strategy.nextDuration() == .milliseconds(5)) // 8 unchanged clamped to max 5
  }
  
  #if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst)) || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Windows)
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
  @Test func constantPrecondition() async {
    await #expect(processExitsWith: .success) {
      _ = Backoff.constant(.milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.constant(.milliseconds(-1))
    }
  }
  
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
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
  
  @available(iOS 16.0, macCatalyst 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
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
  
  @available(iOS 18.0, macCatalyst 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
  @Test func decorrelatedJitterPrecondition() async {
    await #expect(processExitsWith: .success) {
      _ = Backoff.decorrelatedJitter(factor: 1, base: .milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.decorrelatedJitter(factor: 1, base: .milliseconds(-1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.decorrelatedJitter(factor: -1, base: .milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.decorrelatedJitter(factor: -1, base: .milliseconds(-1))
    }
  }
  #endif
}

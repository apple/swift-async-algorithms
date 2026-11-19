import AsyncAlgorithms
import Testing

#if compiler(>=6.2)
@Suite struct BackoffTests {

  @available(AsyncAlgorithms 1.1, *)
  @Test func constantBackoff() {
    var iterator =
      Backoff
      .constant(.milliseconds(5))
      .makeIterator()
    #expect(iterator.nextDuration() == .milliseconds(5))
    #expect(iterator.nextDuration() == .milliseconds(5))
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func linearBackoff() {
    var iterator =
      Backoff
      .linear(increment: .milliseconds(2), initial: .milliseconds(1))
      .makeIterator()
    #expect(iterator.nextDuration() == .milliseconds(1))
    #expect(iterator.nextDuration() == .milliseconds(3))
    #expect(iterator.nextDuration() == .milliseconds(5))
    #expect(iterator.nextDuration() == .milliseconds(7))
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func exponentialBackoff() {
    var iterator =
      Backoff
      .exponential(factor: 2, initial: .milliseconds(1))
      .makeIterator()
    #expect(iterator.nextDuration() == .milliseconds(1))
    #expect(iterator.nextDuration() == .milliseconds(2))
    #expect(iterator.nextDuration() == .milliseconds(4))
    #expect(iterator.nextDuration() == .milliseconds(8))
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func fullJitter() {
    var rng = SplitMix64(seed: 42)
    var iterator =
      Backoff
      .constant(.milliseconds(100))
      .fullJitter()
      .makeIterator()
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 15_991_039_287_692_012))  // 15.99 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 34_419_071_652_363_758))  // 34.41 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 86_822_807_654_653_238))  // 86.82 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 80_063_187_671_350_344))  // 80.06 ms
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func equalJitter() {
    var rng = SplitMix64(seed: 42)
    var iterator =
      Backoff
      .constant(.milliseconds(100))
      .equalJitter()
      .makeIterator()
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 57_995_519_643_846_006))  // 57.99 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 67_209_535_826_181_879))  // 67.20 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 93_411_403_827_326_619))  // 93.41 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 90_031_593_835_675_172))  // 90.03 ms
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func minimum() {
    var iterator =
      Backoff
      .exponential(factor: 2, initial: .milliseconds(1))
      .minimum(.milliseconds(2))
      .makeIterator()
    #expect(iterator.nextDuration() == .milliseconds(2))  // 1 clamped to min 2
    #expect(iterator.nextDuration() == .milliseconds(2))  // 2 unchanged
    #expect(iterator.nextDuration() == .milliseconds(4))  // 4 unchanged
    #expect(iterator.nextDuration() == .milliseconds(8))  // 8 unchanged
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func maximum() {
    var iterator =
      Backoff
      .exponential(factor: 2, initial: .milliseconds(1))
      .maximum(.milliseconds(5))
      .makeIterator()
    #expect(iterator.nextDuration() == .milliseconds(1))  // 1 unchanged
    #expect(iterator.nextDuration() == .milliseconds(2))  // 2 unchanged
    #expect(iterator.nextDuration() == .milliseconds(4))  // 4 unchanged
    #expect(iterator.nextDuration() == .milliseconds(5))  // 8 clamped to max 5
  }
  
  @available(AsyncAlgorithms 1.1, *)
  @Test func fullJitterAndMaximum() {
    var rng = SplitMix64(seed: 42)
    var iterator =
      Backoff
      .constant(.milliseconds(100))
      .fullJitter()
      .maximum(.milliseconds(50))
      .makeIterator()
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 15_991_039_287_692_012))  // 15.99 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 34_419_071_652_363_758))  // 34.41 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 50_000_000_000_000_000))  // 50 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 50_000_000_000_000_000))  // 50 ms
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func equalJitterAndMaximum() {
    var rng = SplitMix64(seed: 42)
    var iterator =
      Backoff
      .constant(.milliseconds(100))
      .equalJitter()
      .maximum(.milliseconds(60))
      .makeIterator()
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 57_995_519_643_846_006))  // 57.99 ms
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 60_000_000_000_000_000))  // 60 ms clamped
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 60_000_000_000_000_000))  // 60 ms clamped
    #expect(iterator.nextDuration(using: &rng) == Duration(attoseconds: 60_000_000_000_000_000))  // 60 ms clamped
  }

  @available(AsyncAlgorithms 1.1, *)
  @Test func overflowSafety() async {
    await #expect(processExitsWith: .success) {
      var iterator =
        Backoff
        .exponential(factor: 2, initial: .seconds(5))
        .maximum(.seconds(120))
        .makeIterator()
      for _ in 0..<1000 {
        _ = iterator.nextDuration()
      }
    }
  }

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
    await #expect(processExitsWith: .failure) {
      _ = Backoff.exponential(factor: 0, initial: .milliseconds(1))
    }
    await #expect(processExitsWith: .failure) {
      _ = Backoff.exponential(factor: -1, initial: .milliseconds(1))
    }
  }
}
#endif

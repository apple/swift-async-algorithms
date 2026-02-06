//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
import AsyncAlgorithms

@available(macOS 15.0, *)
final class TestFlatMapLatest: XCTestCase {

  func test_simple_sequence() async throws {
    let source = [1, 2, 3].async
    let transformed = source.flatMapLatest { intValue in
      return [intValue, intValue * 10].async
    }

    var results: [Int] = []
    for try await element in transformed {
      results.append(element)
    }

    // With synchronous emission, we expect only the last inner sequence [3, 30]
    // However, depending on timing, we might see more intermediate values
    XCTAssertTrue(results.contains(3), "Should contain 3")
    XCTAssertTrue(results.contains(30), "Should contain 30")
    // We should also verify it ends with the last sequence
    XCTAssertEqual(results.suffix(2), [3, 30], "Should end with [3, 30]")
  }

  func test_interleaving_race_condition() async throws {
    // This test simulates a scenario where the inner sequence is slow.
    // In a naive implementation (without generation tracking), the inner task for '1'
    // might wake up and yield AFTER '2' has already started, causing interleaving.

    let source = [1, 2, 3].async
    let transformed = source.flatMapLatest { intValue -> AsyncStream<Int> in
      AsyncStream { continuation in
        Task {
          // Yield the value immediately
          continuation.yield(intValue)

          // Sleep for a bit to allow the outer sequence to move on
          try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

          // Yield a second value - this should be ignored if a new outer value has arrived
          continuation.yield(intValue * 10)
          continuation.finish()
        }
      }
    }

    // We expect:
    // 1 arrives -> starts inner(1) -> yields 1 -> sleeps
    // 2 arrives -> cancels inner(1) -> starts inner(2) -> yields 2 -> sleeps
    // 3 arrives -> cancels inner(2) -> starts inner(3) -> yields 3 -> sleeps
    // inner(3) finishes sleep -> yields 30
    //
    // Ideally, we should NOT see 10 or 20.
    // However, without strict synchronization, we might see them.
    // The strict expectation for flatMapLatest is that once a new value arrives,
    // the old one produces NO MORE values.

    // Note: This test is probabilistic in the naive implementation.
    // It might pass or fail depending on scheduling.
    // But with a correct implementation, it should ALWAYS pass.

    // We'll collect all results to see what happened
    var results: [Int] = []

    for try await element in transformed {
      results.append(element)
    }

    // In the naive implementation, we might get [1, 2, 3, 10, 20, 30] or similar.
    // We want strictly [3, 30] (or [1, 2, 3, 30] depending on how fast the outer sequence is consumed vs produced)
    // Actually, if the outer sequence is consumed fast, we might see intermediate "first" values (1, 2).
    // But we should NEVER see "second" values (10, 20) from cancelled sequences.

    // Let's relax the check to: "Must not contain 10 or 20"
    XCTAssertFalse(results.contains(10), "Should not contain 10 (from cancelled sequence 1)")
    XCTAssertFalse(results.contains(20), "Should not contain 20 (from cancelled sequence 2)")
    XCTAssertTrue(results.contains(30), "Should contain 30 (from final sequence)")
  }
  func test_outer_throwing() async throws {
    let source = AsyncThrowingStream<Int, Error> { continuation in
      Task {
        for value in [1, 2, 3] {
          if value == 2 {
            continuation.finish(throwing: FlatMapLatestFailure())
            return
          }
          continuation.yield(value)
          try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms delay
        }
        continuation.finish()
      }
    }

    let transformed = source.flatMapLatest { intValue in
      return [intValue, intValue * 10].async
    }

    do {
      for try await _ in transformed {}
      XCTFail("Should have thrown")
    } catch {
      XCTAssertEqual(error as? FlatMapLatestFailure, FlatMapLatestFailure())
    }
  }

  func test_inner_throwing() async throws {
    let source = AsyncStream<Int> { continuation in
      Task {
        for value in [1, 2, 3] {
          continuation.yield(value)
          try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms delay between outer values
        }
        continuation.finish()
      }
    }

    let transformed = source.flatMapLatest { intValue in
      return [intValue].async.map { try $0.throwIf(2) }
    }

    do {
      for try await _ in transformed {}
      XCTFail("Should have thrown")
    } catch {
      XCTAssertEqual(error as? FlatMapLatestFailure, FlatMapLatestFailure())
    }
  }

  func test_cancellation() async throws {
    let source = [1, 2, 3].async
    let transformed = source.flatMapLatest { intValue in
      return [intValue].async
    }

    let task = Task {
      for try await _ in transformed {}
    }

    task.cancel()

    do {
      try await task.value
    } catch is CancellationError {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func test_empty_outer() async throws {
    let source = [].async.map { $0 as Int }
    let transformed = source.flatMapLatest { intValue in
      return [intValue].async
    }

    var count = 0
    for try await _ in transformed {
      count += 1
    }
    XCTAssertEqual(count, 0)
  }

  func test_empty_inner() async throws {
    let source = [1, 2, 3].async
    let transformed = source.flatMapLatest { _ in
      return [].async.map { $0 as Int }
    }

    var count = 0
    for try await _ in transformed {
      count += 1
    }
    XCTAssertEqual(count, 0)
  }
  func test_concurrency_crash_repro() async throws {
    // This test simulates the exact race condition where an inner stream producer
    // mimics the behavior of Firestore/Combine publisher wrappers that might
    // yield values or finish asynchronously relative to cancellation.

    @Sendable func innerStream(for user: String) -> AsyncThrowingStream<Int, Error> {
      return AsyncThrowingStream { continuation in
        let task = Task {
          for i in 0...100 {
            // Artificial delay to allow overlap/interleaving
            // This is critical to hit the race condition window
            try await Task.sleep(nanoseconds: 1_000_000)  // 1ms

            continuation.yield(i)
          }
          continuation.finish()
        }

        continuation.onTermination = { @Sendable termination in
          task.cancel()
        }
      }
    }

    let authStream = AsyncStream<String> { continuation in
      continuation.yield("A")
      Task {
        // Yielding again triggers the switch (and cancellation of the previous inner stream)
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        continuation.yield("B")
        try? await Task.sleep(nanoseconds: 10_000_000)
        continuation.finish()
      }
    }

    let combined = authStream.flatMapLatest { user in
      innerStream(for: user)
    }

    // Determine success by running without crashing
    for try await _ in combined {}
  }
}

private struct FlatMapLatestFailure: Error, Equatable {}

extension Int {
  fileprivate func throwIf(_ value: Int) throws -> Int {
    if self == value {
      throw FlatMapLatestFailure()
    }
    return self
  }
}

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

    var expected = [3, 30]
    do {
      for try await element in transformed {
        let (e, ex) = (element, expected.removeFirst())
        print("\(e) == \(ex)")
        
        XCTAssertEqual(e, ex)
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(expected.isEmpty)
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
          try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
          
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
    
    var expected = [3, 30] // We only want the latest
    
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
}

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

final class TestAdjacentPairs: XCTestCase {
  func test_adjacentPairs_produces_tuples_of_adjacent_values_of_original_element() async {
    let source = 1...5
    let expected = Array(zip(source, source.dropFirst()))

    let sequence = source.async.adjacentPairs()
    var actual: [(Int, Int)] = []
    for await item in sequence {
      actual.append(item)
    }

    XCTAssertEqual(expected, actual)
  }

  func test_adjacentPairs_forwards_termination_from_source_when_iteration_is_finished() async {
    let source = 1...5

    var iterator = source.async.adjacentPairs().makeAsyncIterator()
    while let _ = await iterator.next() {}

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_adjacentPairs_produces_empty_sequence_when_source_sequence_is_empty() async {
    let source = 0..<1
    let expected: [(Int, Int)] = []

    let sequence = source.async.adjacentPairs()
    var actual: [(Int, Int)] = []
    for await item in sequence {
      actual.append(item)
    }

    XCTAssertEqual(expected, actual)
  }

  func test_adjacentPairs_throws_when_source_sequence_throws() async throws {
    let source = 1...5
    let expected = [(1, 2), (2, 3)]

    let sequence = source.async.map { try throwOn(4, $0) }.adjacentPairs()
    var iterator = sequence.makeAsyncIterator()
    var actual = [(Int, Int)]()
    do {
      while let value = try await iterator.next() {
        actual.append(value)
      }
      XCTFail(".adjacentPairs should throw when the source sequence throws")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }

    XCTAssertEqual(actual, expected)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_adjacentPairs_finishes_when_iteration_task_is_cancelled() async {
    let source = Indefinite(value: 0)
    let sequence = source.async.adjacentPairs()
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let task = Task {
      var firstIteration = false
      for await _ in sequence {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }

    // ensure the other task actually starts

    await fulfillment(of: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    await fulfillment(of: [finished], timeout: 1.0)
  }

  @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
  @MainActor
  func test_adjacentPairs_next_with_nil_isolation_produces_correct_pairs() async throws {
    let reportingSequence = ReportingAsyncSequence([1, 2])
    let adjacentPairs = reportingSequence.adjacentPairs()
    let iterated = expectation(description: "iterates once")

    let t = Task.immediate {
      for await (previous, current) in adjacentPairs {
        XCTAssertEqual(previous, 1)
        XCTAssertEqual(current, 2)
        iterated.fulfill()
      }
    }

    XCTAssert(reportingSequence.elements.isEmpty, "With a proper implementation of next(isolaton:), elements should be immediately consumed")
    let nonIsolatedNextCalled = reportingSequence.events.contains {
      switch $0 {
      case .next:
        true
      default:
        false
      }
    }
    XCTAssertFalse(nonIsolatedNextCalled, "Next without isolation should not be called with a fully isolated pipeline")

    await fulfillment(of: [iterated], timeout: 1.0)
    t.cancel()
  }
}

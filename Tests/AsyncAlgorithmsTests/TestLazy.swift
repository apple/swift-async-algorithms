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

final class TestLazy: XCTestCase {
  func test_lazy_outputs_elements_and_finishes_when_source_is_array() async {
    let expected = [1, 2, 3, 4]
    let sequence = expected.async

    var collected = [Int]()
    for await item in sequence {
      collected.append(item)
    }

    XCTAssertEqual(expected, collected)
  }

  func test_lazy_outputs_elements_and_finishes_when_source_is_set() async {
    let expected: Set = [1, 2, 3, 4]
    let sequence = expected.async

    var collected = Set<Int>()
    for await item in sequence {
      collected.insert(item)
    }

    XCTAssertEqual(expected, collected)
  }

  func test_lazy_finishes_without_elements_when_source_is_empty() async {
    let expected = [Int]()
    let sequence = expected.async

    var collected = [Int]()
    for await item in sequence {
      collected.append(item)
    }

    XCTAssertEqual(expected, collected)
  }

  func test_lazy_triggers_expected_iterator_events_when_source_is_iterated() async {
    let expected = [1, 2, 3]
    let expectedEvents = [
      ReportingSequence<Int>.Event.makeIterator,
      .next,
      .next,
      .next,
      .next,
    ]
    let source = ReportingSequence(expected)
    let sequence = source.async

    XCTAssertEqual(source.events, [])

    var collected = [Int]()
    for await item in sequence {
      collected.append(item)
    }

    XCTAssertEqual(expected, collected)
    XCTAssertEqual(expectedEvents, source.events)
  }

  func test_lazy_stops_triggering_iterator_events_when_source_is_pastEnd() async {
    let expected = [1, 2, 3]
    let expectedEvents = [
      ReportingSequence<Int>.Event.makeIterator,
      .next,
      .next,
      .next,
      .next,
    ]
    let source = ReportingSequence(expected)
    let sequence = source.async

    XCTAssertEqual(source.events, [])

    var collected = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }

    XCTAssertEqual(expected, collected)
    XCTAssertEqual(expectedEvents, source.events)

    let pastEnd = await iterator.next()

    XCTAssertEqual(pastEnd, nil)
    // ensure that iterating past the end does not invoke next again
    XCTAssertEqual(expectedEvents, source.events)
  }

  func test_lazy_finishes_when_task_is_cancelled() async {
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let source = Indefinite(value: "test")
    let sequence = source.async

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
}

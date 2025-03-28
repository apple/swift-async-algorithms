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

final class TestCompacted: XCTestCase {
  func test_compacted_is_equivalent_to_compactMap_when_input_as_nil_elements() async {
    let source = [1, 2, nil, 3, 4, nil, 5]
    let expected = source.compactMap { $0 }
    let sequence = source.async.compacted()
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
  }

  func test_compacted_produces_nil_next_element_when_iteration_is_finished() async {
    let source = [1, 2, nil, 3, 4, nil, 5]
    let expected = source.compactMap { $0 }
    let sequence = source.async.compacted()
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_compacted_is_equivalent_to_compactMap_when_input_as_no_nil_elements() async {
    let source: [Int?] = [1, 2, 3, 4, 5]
    let expected = source.compactMap { $0 }
    let sequence = source.async.compacted()
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
  }

  func test_compacted_throws_when_root_sequence_throws() async throws {
    let sequence = [1, nil, 3, 4, 5, nil, 7].async.map { try throwOn(4, $0) }.compacted()
    var iterator = sequence.makeAsyncIterator()
    var collected = [Int]()
    do {
      while let value = try await iterator.next() {
        collected.append(value)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    XCTAssertEqual(collected, [1, 3])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_compacted_finishes_when_iteration_task_is_cancelled() async {
    let value: String? = "test"
    let source = Indefinite(value: value)
    let sequence = source.async.compacted()
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
}

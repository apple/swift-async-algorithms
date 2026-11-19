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
import AsyncSequenceValidation

final class TestEnumerated: XCTestCase {
  func testEnumerate() async {
    let source = ["a", "b", "c", "d"]
    let enumerated = source.async.enumerated()
    var actual = [(Int, String)]()
    var iterator = enumerated.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(actual, .init(source.enumerated()))
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func testEmpty() async {
    let source = [String]()
    let enumerated = source.async.enumerated()
    var iterator = enumerated.makeAsyncIterator()
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func testEnumeratedThrowsWhenBaseSequenceThrows() async throws {
    let sequence = ["a", "b", "c", "d"].async.map { try throwOn("c", $0) }.enumerated()
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    XCTAssertEqual(collected, [(0, "a"), (1, "b")])

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func testEnumeratedFinishesWhenCancelled() {
    let source = Indefinite(value: "a")
    let sequence = source.async.enumerated()
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
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

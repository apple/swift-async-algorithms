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

@preconcurrency import XCTest
import AsyncAlgorithms

final class TestInterspersed: XCTestCase {
  func test_interspersed() async {
    let source = [1, 2, 3, 4, 5]
    let expected = [1, 0, 2, 0, 3, 0, 4, 0, 5]
    let sequence = source.async.interspersed(with: 0)
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_empty() async {
    let source = [Int]()
    let expected = [Int]()
    let sequence = source.async.interspersed(with: 0)
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_with_throwing_upstream() async {
    let source = [1, 2, 3, -1, 4, 5]
    let expected = [1, 0, 2, 0, 3, 0]
    var actual = [Int]()
    let sequence = source.async.map {
      try throwOn(-1, $0)
    }.interspersed(with: 0)

    var iterator = sequence.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try! await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_cancellation() async {
    let source = Indefinite(value: "test")
    let sequence = source.async.interspersed(with: "sep")
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")
    let task = Task {

      var iterator = sequence.makeAsyncIterator()
      let _ = await iterator.next()
      iterated.fulfill()

      while let _ = await iterator.next() { }

      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)

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

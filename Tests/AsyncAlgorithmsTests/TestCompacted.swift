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
  func test_compacting() async {
    let source = [1, 2, nil, 3, 4, nil, 5]
    let expected = source.compactMap { $0 }
    let sequence = source.async.compacted()
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
  }
  
  func test_compacting_past_end() async {
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
  
  func test_compactingNonNils() async {
    let source: [Int?] = [1, 2, 3, 4, 5]
    let expected = source.compactMap { $0 }
    let sequence = source.async.compacted()
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
  }
  
  func test_cancellation() async {
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
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

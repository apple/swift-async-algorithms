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

final class TestLazy: XCTestCase {
  func test_array() async {
    let source = [1, 2, 3, 4]
    let expected = source
    let sequence = source.async
    
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    
    XCTAssertEqual(expected, actual)
  }
  
  func test_set() async {
    let source: Set = [1, 2, 3, 4]
    let expected = source
    let sequence = source.async
    
    var actual = Set<Int>()
    for await item in sequence {
      actual.insert(item)
    }
    
    XCTAssertEqual(expected, actual)
  }
  
  func test_empty() async {
    let source = EmptyCollection<Int>()
    let expected = [Int]()
    let sequence = source.async
    
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    
    XCTAssertEqual(expected, actual)
  }
  
  func test_iteration() async {
    let source = ReportingSequence([1, 2, 3])
    let sequence = source.async
    XCTAssertEqual(source.events, [])
    var collected = [Int]()
    for await item in sequence {
      collected.append(item)
    }
    XCTAssertEqual(collected, [1, 2, 3])
    XCTAssertEqual(source.events, [
      .makeIterator,
      .next,
      .next,
      .next,
      .next
    ])
  }
  
  func test_manual_iteration() async {
    let source = ReportingSequence([1, 2, 3])
    let sequence = source.async
    XCTAssertEqual(source.events, [])
    var collected = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(collected, [1, 2, 3])
    XCTAssertEqual(source.events, [
      .makeIterator,
      .next,
      .next,
      .next,
      .next
    ])
    let pastEnd = await iterator.next()
    XCTAssertEqual(pastEnd, nil)
    // ensure that iterating past the end does not invoke next again
    XCTAssertEqual(source.events, [
      .makeIterator,
      .next,
      .next,
      .next,
      .next
    ])
  }
  
  func test_cancellation() async {
    let source = Indefinite(value: "test")
    let sequence = source.async
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

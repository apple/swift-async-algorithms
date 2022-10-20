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

final class TestDeferred: XCTestCase {
  func test_deferred() async {
    let expected = [0,1,2,3,4]
    let sequence = deferred {
      return expected.async
    }
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
  }
  
  func test_deferred_remains_idle_pending_consumer() async {
    let expectation = expectation(description: "pending")
    expectation.isInverted = true
    let _ = deferred {
      AsyncStream { continuation in
        expectation.fulfill()
        continuation.yield(0)
        continuation.finish()
      }
    }
    wait(for: [expectation], timeout: 1.0)
  }
  
  func test_deferred_generates_new_sequence_per_consumer() async {
    let expectation = expectation(description: "started")
    expectation.expectedFulfillmentCount = 3
    let sequence = deferred {
      AsyncStream { continuation in
        expectation.fulfill()
        continuation.yield(0)
        continuation.finish()
      }
    }
    for await _ in sequence { }
    for await _ in sequence { }
    for await _ in sequence { }
    wait(for: [expectation], timeout: 1.0)
  }
  
  func test_deferred_throws() async {
    let expectation = expectation(description: "throws")
    let sequence = deferred {
      AsyncThrowingStream<Void, Error> { continuation in
        continuation.finish(throwing: Failure())
      }
    }
    do {
      for try await _ in sequence { }
    }
    catch {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1.0)
  }
  
  func test_deferred_autoclosure() async {
    let expected = [0,1,2,3,4]
    let sequence = deferred(expected.async)
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
  }
}

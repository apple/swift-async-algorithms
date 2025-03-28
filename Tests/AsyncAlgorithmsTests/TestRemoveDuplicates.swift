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

final class TestRemoveDuplicates: XCTestCase {
  func test_removeDuplicates() async {
    let source = [1, 2, 2, 2, 3, 4, 5, 6, 5, 5]
    let expected = [1, 2, 3, 4, 5, 6, 5]
    let sequence = source.async.removeDuplicates()
    var actual = [Int]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(actual, expected)
  }

  func test_removeDuplicates_with_closure() async {
    let source = [1, 2.001, 2.005, 2.011, 3, 4, 5, 6, 5, 5]
    let expected = [1, 2.001, 2.011, 3, 4, 5, 6, 5]
    let sequence = source.async.removeDuplicates { abs($0 - $1) < 0.01 }
    var actual = [Double]()
    for await item in sequence {
      actual.append(item)
    }
    XCTAssertEqual(actual, expected)
  }

  func test_removeDuplicates_with_throwing_closure() async {
    let source = [1, 2, 2, 2, 3, -1, 5, 6, 5, 5]
    let expected = [1, 2, 3]
    var actual = [Int]()
    let sequence = source.async.removeDuplicates { prev, next in
      let next = try throwOn(-1, next)
      return prev == next
    }

    do {
      for try await item in sequence {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(actual, expected)
  }

  func test_removeDuplicates_with_throwing_upstream() async {
    let source = [1, 2, 2, 2, 3, -1, 5, 6, 5, 5]
    let expected = [1, 2, 3]
    var actual = [Int]()
    let throwingSequence = source.async.map(
      {
        if $0 < 0 {
          throw NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil)
        }
        return $0
      } as @Sendable (Int) throws -> Int
    )

    do {
      for try await item in throwingSequence.removeDuplicates() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual((error as NSError).code, -1)
    }
    XCTAssertEqual(actual, expected)
  }

  func test_removeDuplicates_cancellation() async {
    let source = Indefinite(value: "test")
    let sequence = source.async.removeDuplicates()
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")
    let task = Task {
      var firstIteration = false
      for await _ in sequence {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        } else {
          XCTFail("This sequence should only ever emit a single value")
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

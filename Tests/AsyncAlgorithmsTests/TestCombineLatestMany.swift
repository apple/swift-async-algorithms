//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.2)

import XCTest
import AsyncAlgorithms

@available(AsyncAlgorithms 1.1, *)
final class TestCombineLatestMany: XCTestCase {
  func test_combineLatest() async throws {
    let a = [1, 2, 3].async
    let b = [4, 5, 6].async
    let c = [7, 8, 9].async
    let sequence = combineLatestMany([a, b, c])
    let actual = await Array(sequence)
    XCTAssertGreaterThanOrEqual(actual.count, 3)
  }

  func test_ordering1() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence([4, 5, 6])
    var c = GatedSequence([7, 8, 9])
    let finished = expectation(description: "finished")
    let sequence = combineLatestMany([a, b, c])
    let validator = Validator<[Int]>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next(isolation: nil)
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [[1, 4, 7]])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [[1, 4, 7], [2, 4, 7]])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [[1, 4, 7], [2, 4, 7], [2, 5, 7]])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [[1, 4, 7], [2, 4, 7], [2, 5, 7], [2, 5, 8]])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [[1, 4, 7], [2, 4, 7], [2, 5, 7], [2, 5, 8], [3, 5, 8]])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [[1, 4, 7], [2, 4, 7], [2, 5, 7], [2, 5, 8], [3, 5, 8], [3, 6, 8]])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(
      value,
      [[1, 4, 7], [2, 4, 7], [2, 5, 7], [2, 5, 8], [3, 5, 8], [3, 6, 8], [3, 6, 9]]
    )

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(
      value,
      [[1, 4, 7], [2, 4, 7], [2, 5, 7], [2, 5, 8], [3, 5, 8], [3, 6, 8], [3, 6, 9]]
    )
  }
}

#endif

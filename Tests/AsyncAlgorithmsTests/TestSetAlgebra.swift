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

final class TestSetAlgebra: XCTestCase {
  func test_Set() async {
    let source = [1, 2, 3]
    let expected = Set(source)
    let actual = await Set(source.async)
    XCTAssertEqual(expected, actual)
  }

  func test_Set_duplicate() async {
    let source = [1, 2, 3, 3]
    let expected = Set(source)
    let actual = await Set(source.async)
    XCTAssertEqual(expected, actual)
  }

  func test_IndexSet() async {
    let source = [1, 2, 3]
    let expected = IndexSet(source)
    let actual = await IndexSet(source.async)
    XCTAssertEqual(expected, actual)
  }

  func test_throwing() async {
    let source = Array([1, 2, 3, 4, 5, 6])
    let input = source.async.map { (value: Int) async throws -> Int in
      if value == 4 { throw NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil) }
      return value
    }
    do {
      _ = try await Set(input)
      XCTFail()
    } catch {
      XCTAssertEqual((error as NSError).code, -1)
    }
  }
}

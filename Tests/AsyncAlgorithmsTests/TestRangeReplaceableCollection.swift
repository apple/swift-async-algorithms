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

final class TestRangeReplaceableCollection: XCTestCase {
  func test_String() async {
    let source = "abc"
    let expected = source
    let actual = await String(source.async)
    XCTAssertEqual(expected, actual)
  }

  func test_Data() async {
    let source = Data([1, 2, 3])
    let expected = source
    let actual = await Data(source.async)
    XCTAssertEqual(expected, actual)
  }

  func test_ContiguousArray() async {
    let source = ContiguousArray([1, 2, 3])
    let expected = source
    let actual = await ContiguousArray(source.async)
    XCTAssertEqual(expected, actual)
  }

  func test_Array() async {
    let source = Array([1, 2, 3])
    let expected = source
    let actual = await Array(source.async)
    XCTAssertEqual(expected, actual)
  }

  func test_throwing() async {
    let source = Array([1, 2, 3, 4, 5, 6])
    let input = source.async.map { (value: Int) async throws -> Int in
      if value == 4 { throw NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil) }
      return value
    }
    do {
      _ = try await Array(input)
      XCTFail()
    } catch {
      XCTAssertEqual((error as NSError).code, -1)
    }
  }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
import AsyncAlgorithms

final class TestRangeReplacableCollection: XCTestCase {
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
}

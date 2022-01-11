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
}

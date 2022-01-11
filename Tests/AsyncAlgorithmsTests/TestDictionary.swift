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

final class TestDictionary: XCTestCase {
  func test_uniqueKeysAndValues() async {
    let source = [(1, "a"), (2, "b"), (3, "c")]
    let expected = Dictionary(uniqueKeysWithValues: source)
    let actual = await Dictionary(uniqueKeysWithValues: source.async)
    XCTAssertEqual(expected, actual)
  }
  
  func test_uniqingWith() async {
    let source = [("a", 1), ("b", 2), ("a", 3), ("b", 4)]
    let expected = Dictionary(source) { first, _ in first }
    let actual = await Dictionary(source.async) { first, _ in first }
    XCTAssertEqual(expected, actual)
  }
  
  func test_grouping() async {
    let source = ["Kofi", "Abena", "Efua", "Kweku", "Akosua"]
    let expected = Dictionary(grouping: source, by: { $0.first! })
    let actual = await Dictionary(grouping: source.async, by: { $0.first! })
    XCTAssertEqual(expected, actual)
  }
}

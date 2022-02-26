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

final class TestBuffer: XCTestCase {
  actor Isolated<T> {
    var value: T
    
    init(_ value: T) {
      self.value = value
    }
    
    func update(_ apply: @Sendable (inout T) -> Void) async {
      apply(&value)
    }
  }
  func test_buffering() async {
    var gated = GatedSequence([1, 2, 3, 4, 5])
    let sequence = gated.buffer()
    var iterator = sequence.makeAsyncIterator()
    
    gated.advance()
    var value = await iterator.next()
    XCTAssertEqual(value, 1)
    gated.advance()
    gated.advance()
    gated.advance()
    value = await iterator.next()
    XCTAssertEqual(value, 2)
    value = await iterator.next()
    XCTAssertEqual(value, 3)
    value = await iterator.next()
    XCTAssertEqual(value, 4)
    gated.advance()
    gated.advance()
    value = await iterator.next()
    XCTAssertEqual(value, 5)
    value = await iterator.next()
    XCTAssertEqual(value, nil)
    value = await iterator.next()
    XCTAssertEqual(value, nil)
  }
}

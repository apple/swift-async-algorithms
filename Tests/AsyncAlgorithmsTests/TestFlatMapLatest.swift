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

@available(macOS 15.0, *)
final class TestFlatMapLatest: XCTestCase {
  
  func test_simple_sequence() async throws {
    let source = [1, 2, 3].async
    let transformed = source.flatMapLatest { intValue in
      return [intValue, intValue * 10].async
    }

    var expected = [3, 30]
    do {
      for try await element in transformed {
        let (e, ex) = (element, expected.removeFirst())
        print("\(e) == \(ex)")
        
        XCTAssertEqual(e, ex)
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(expected.isEmpty)
  }

}

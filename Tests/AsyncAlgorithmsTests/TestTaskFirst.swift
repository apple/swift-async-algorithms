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

final class TestTaskFirst: XCTestCase {
  func test_first() async {
    let firstValue = await Task.first(Task {
      return 1
    }, Task {
      try! await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)
      return 2
    })
    XCTAssertEqual(firstValue, 1)
  }
  
  func test_second() async {
    let firstValue = await Task.first(Task {
      try! await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)
      return 1
    }, Task {
      return 2
    })
    XCTAssertEqual(firstValue, 2)
  }

  func test_throwing() async {
    do {
      _ = try await Task.first(Task { () async throws -> Int in
        try await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)
        return 1
      }, Task { () async throws -> Int in
        throw NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil)
      })
      XCTFail()
    } catch {
      XCTAssertEqual((error as NSError).code, -1)
    }
  }
}

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

final class TestAsyncSequence: XCTestCase {
  func test_throwing_waitForAll() async throws {
    let source = 1...5

    let sequence = source.async.map {
      _ = try throwOn(4, $0)
      return ()
    }
    do {
      try await sequence.waitForAll()
    } catch {
      XCTAssertTrue(error is Failure)
    }
  }
}

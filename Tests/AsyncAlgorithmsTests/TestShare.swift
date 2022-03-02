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

final class TestShare: XCTestCase {
  func test_replication() async {
    var base = GatedSequence([1, 2, 3, 4, 5])
    let shared = base.share(3)
    let t1 = Task<[Int], Never> {
      await Array(shared[0])
    }
    let t2 = Task<[Int], Never> {
      await Array(shared[1])
    }
    let t3 = Task<[Int], Never> {
      await Array(shared[2])
    }
    for _ in 0..<6 {
      base.advance()
    }
    let r1 = await t1.value
    let r2 = await t2.value
    let r3 = await t3.value
    XCTAssertEqual(r1, [1, 2, 3, 4, 5])
    XCTAssertEqual(r2, [1, 2, 3, 4, 5])
    XCTAssertEqual(r3, [1, 2, 3, 4, 5])
  }
  
  func test_failure_replication() async {
    var base = GatedSequence([1, 2, 3, 4, 5])
    let shared = base.map { try throwOn(3, $0) }.share(3)
    let t1 = Task<[Int], Error> {
      try await Array(shared[0])
    }
    let t2 = Task<[Int], Error> {
      try await Array(shared[1])
    }
    let t3 = Task<[Int], Error> {
      try await Array(shared[2])
    }
    for _ in 0..<6 {
      base.advance()
    }
    do {
      _ = try await t1.value
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    do {
      _ = try await t2.value
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    do {
      _ = try await t3.value
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }
}

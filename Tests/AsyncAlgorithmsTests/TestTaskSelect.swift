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

@preconcurrency import XCTest
import Dispatch
import AsyncAlgorithms

final class TestTaskSelect: XCTestCase {
  func test_first() async {
    let firstValue = await Task.select(Task {
      return 1
    }, Task {
      try! await Task.sleep(until: .now + .seconds(2), clock: .continuous)
      return 2
    }).value
    XCTAssertEqual(firstValue, 1)
  }
  
  func test_second() async {
    let firstValue = await Task.select(Task {
      try! await Task.sleep(until: .now + .seconds(2), clock: .continuous)
      return 1
    }, Task {
      return 2
    }).value
    XCTAssertEqual(firstValue, 2)
  }

  func test_throwing() async {
    do {
      _ = try await Task.select(Task { () async throws -> Int in
        try await Task.sleep(until: .now + .seconds(2), clock: .continuous)
        return 1
      }, Task { () async throws -> Int in
        throw NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil)
      }).value
      XCTFail()
    } catch {
      XCTAssertEqual((error as NSError).code, -1)
    }
  }
  
  func test_cancellation() async {
    let firstReady = expectation(description: "first ready")
    let secondReady = expectation(description: "second ready")
    let firstCancelled = expectation(description: "first cancelled")
    let secondCancelled = expectation(description: "second cancelled")
    let task = Task {
      _ = await Task.select(Task {
        await withTaskCancellationHandler {
          firstCancelled.fulfill()
        } operation: { () -> Int in
          firstReady.fulfill()
          try? await Task.sleep(until: .now + .seconds(2), clock: .continuous)
          return 1
        }
      }, Task {
        await withTaskCancellationHandler {
          secondCancelled.fulfill()
        } operation: { () -> Int in
          secondReady.fulfill()
          try? await Task.sleep(until: .now + .seconds(2), clock: .continuous)
          return 1
        }
      })
    }
    wait(for: [firstReady, secondReady], timeout: 1.0)
    task.cancel()
    wait(for: [firstCancelled, secondCancelled], timeout: 1.0)
  }
}

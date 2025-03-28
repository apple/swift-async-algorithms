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

final class TestManualClock: XCTestCase {
  func test_sleep() async {
    let clock = ManualClock()
    let start = clock.now
    let afterSleep = expectation(description: "after sleep")
    let state = ManagedCriticalState(false)
    Task {
      try await clock.sleep(until: start.advanced(by: .steps(3)))
      state.withCriticalRegion { $0 = true }
      afterSleep.fulfill()
    }
    XCTAssertFalse(state.withCriticalRegion { $0 })
    clock.advance()
    XCTAssertFalse(state.withCriticalRegion { $0 })
    clock.advance()
    XCTAssertFalse(state.withCriticalRegion { $0 })
    clock.advance()
    await fulfillment(of: [afterSleep], timeout: 1.0)
    XCTAssertTrue(state.withCriticalRegion { $0 })
  }

  func test_sleep_cancel() async {
    let clock = ManualClock()
    let start = clock.now
    let afterSleep = expectation(description: "after sleep")
    let state = ManagedCriticalState(false)
    let failure = ManagedCriticalState<Error?>(nil)
    let task = Task {
      do {
        try await clock.sleep(until: start.advanced(by: .steps(3)))
      } catch {
        failure.withCriticalRegion { $0 = error }
      }
      state.withCriticalRegion { $0 = true }
      afterSleep.fulfill()
    }
    XCTAssertFalse(state.withCriticalRegion { $0 })
    clock.advance()
    task.cancel()
    await fulfillment(of: [afterSleep], timeout: 1.0)
    XCTAssertTrue(state.withCriticalRegion { $0 })
    XCTAssertTrue(failure.withCriticalRegion { $0 is CancellationError })
  }

  func test_sleep_cancel_before_advance() async {
    let clock = ManualClock()
    let start = clock.now
    let afterSleep = expectation(description: "after sleep")
    let state = ManagedCriticalState(false)
    let failure = ManagedCriticalState<Error?>(nil)
    let task = Task {
      do {
        try await clock.sleep(until: start.advanced(by: .steps(3)))
      } catch {
        failure.withCriticalRegion { $0 = error }
      }
      state.withCriticalRegion { $0 = true }
      afterSleep.fulfill()
    }
    XCTAssertFalse(state.withCriticalRegion { $0 })
    task.cancel()
    await fulfillment(of: [afterSleep], timeout: 1.0)
    XCTAssertTrue(state.withCriticalRegion { $0 })
    XCTAssertTrue(failure.withCriticalRegion { $0 is CancellationError })
  }
}

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

final class TestValidator: XCTestCase {
  func test_gate() async {
    let gate = Gate()
    let state = ManagedCriticalState(false)
    let entered = expectation(description: "entered")
    Task {
      await gate.enter()
      state.withCriticalRegion { $0 = true }
      entered.fulfill()
    }
    XCTAssertFalse(state.withCriticalRegion { $0 })
    gate.open()
    await fulfillment(of: [entered], timeout: 1.0)
    XCTAssertTrue(state.withCriticalRegion { $0 })
  }

  func test_gatedSequence() async {
    var gated = GatedSequence([1, 2, 3])
    let expectations = [
      expectation(description: "item 1"),
      expectation(description: "item 2"),
      expectation(description: "item 3"),
    ]
    let started = expectation(description: "started")
    let finished = expectation(description: "finished")
    let state = ManagedCriticalState([Int]())
    let seq = gated
    Task {
      var iterator = seq.makeAsyncIterator()
      var index = 0
      started.fulfill()
      while let value = await iterator.next() {
        state.withCriticalRegion {
          $0.append(value)
        }
        expectations[index].fulfill()
        index += 1
      }
      finished.fulfill()
    }
    await fulfillment(of: [started], timeout: 1.0)
    XCTAssertEqual(state.withCriticalRegion { $0 }, [])
    gated.advance()
    await fulfillment(of: [expectations[0]], timeout: 1.0)
    XCTAssertEqual(state.withCriticalRegion { $0 }, [1])
    gated.advance()
    await fulfillment(of: [expectations[1]], timeout: 1.0)
    XCTAssertEqual(state.withCriticalRegion { $0 }, [1, 2])
    gated.advance()
    await fulfillment(of: [expectations[2]], timeout: 1.0)
    XCTAssertEqual(state.withCriticalRegion { $0 }, [1, 2, 3])
    await fulfillment(of: [finished], timeout: 1.0)
  }

  func test_gatedSequence_throwing() async {
    var gated = GatedSequence([1, 2, 3])
    let expectations = [
      expectation(description: "item 1")
    ]
    let started = expectation(description: "started")
    let finished = expectation(description: "finished")
    let state = ManagedCriticalState([Int]())
    let failure = ManagedCriticalState<Error?>(nil)
    let seq = gated.map { try throwOn(2, $0) }
    Task {
      var iterator = seq.makeAsyncIterator()
      var index = 0
      started.fulfill()
      do {
        while let value = try await iterator.next() {
          state.withCriticalRegion {
            $0.append(value)
          }
          expectations[index].fulfill()
          index += 1
        }
      } catch {
        failure.withCriticalRegion { $0 = error }
      }
      finished.fulfill()
    }
    await fulfillment(of: [started], timeout: 1.0)
    XCTAssertEqual(state.withCriticalRegion { $0 }, [])
    gated.advance()
    await fulfillment(of: [expectations[0]], timeout: 1.0)
    XCTAssertEqual(state.withCriticalRegion { $0 }, [1])
    gated.advance()
    XCTAssertEqual(state.withCriticalRegion { $0 }, [1])
    await fulfillment(of: [finished], timeout: 1.0)
    XCTAssertEqual(state.withCriticalRegion { $0 }, [1])
    XCTAssertEqual(failure.withCriticalRegion { $0 as? Failure }, Failure())
  }

  func test_validator() async {
    var a = GatedSequence([1, 2, 3])
    let finished = expectation(description: "finished")
    let sequence = a.map { $0 + 1 }
    let validator = Validator<Int>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [2])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [2, 3])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [2, 3, 4])
    a.advance()

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [2, 3, 4])
  }
}

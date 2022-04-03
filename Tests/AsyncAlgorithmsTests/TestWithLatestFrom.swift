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

@testable import AsyncAlgorithms
@preconcurrency import XCTest

final class TestWithLatestFrom: XCTestCase {
  func test_withLatestFrom_uses_latest_element_from_other() async {
    // Timeline
    // base:     -0---1    -2    -----3    ---4-----x--|
    // other:    ---a--    --    -b-c--    -x----------|
    // expected: -----(1,a)-(2,a)-----(3,c)---(4,c)-x--|
    let baseHasProduced0 = expectation(description: "Base has produced 0")

    let otherHasProducedA = expectation(description: "Other has produced 'a'")
    let otherHasProducedC = expectation(description: "Other has produced 'c'")

    let base = AsyncChannel<Int>()
    let other = AsyncChannel<String>()

    let sequence = base.withLatest(from: other)
    var iterator = sequence.makeAsyncIterator()

    // expectations that ensure that "other" has really delivered
    // its elements before requesting the next element from "base"
    iterator.onOtherElement = { @Sendable element in
      if element == "a" {
        otherHasProducedA.fulfill()
      }

      if element == "c" {
        otherHasProducedC.fulfill()
      }
    }

    iterator.onBaseElement = { @Sendable element in
      if element == 0 {
        baseHasProduced0.fulfill()
      }
    }

    Task {
      await base.send(0)
      wait(for: [baseHasProduced0], timeout: 1.0)
      await other.send("a")
      wait(for: [otherHasProducedA], timeout: 1.0)
      await base.send(1)
    }

    let element1 = await iterator.next()
    XCTAssertEqual(element1!, (1, "a"))

    Task {
      await base.send(2)
    }

    let element2 = await iterator.next()
    XCTAssertEqual(element2!, (2, "a"))

    Task {
      await other.send("b")
      await other.send("c")
      wait(for: [otherHasProducedC], timeout: 1.0)
      await base.send(3)
    }

    let element3 = await iterator.next()
    XCTAssertEqual(element3!, (3, "c"))

    Task {
      other.finish()
      await base.send(4)
    }

    let element4 = await iterator.next()
    XCTAssertEqual(element4!, (4, "c"))

    base.finish()

    let element5 = await iterator.next()
    XCTAssertNil(element5)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_throws_when_base_throws_and_pastEnd_is_nil() async throws {
    let base = [1, 2, 3]
    let other = Indefinite(value: "a")

    let sequence = base.async.map { try throwOn(1, $0) }.withLatest(from: other.async)
    var iterator = sequence.makeAsyncIterator()

    do {
      let value = try await iterator.next()
      XCTFail("got \(value as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_throws_when_other_throws_and_pastEnd_is_nil() async throws {
    let base = Indefinite(value: 1)
    let other = AsyncThrowingChannel<String, Error>()
    let sequence = base.async.withLatest(from: other)
    var iterator = sequence.makeAsyncIterator()

    other.fail(Failure())

    do {
      var element: (Int, String)?
      repeat {
        element = try await iterator.next()
      } while element == nil
      XCTFail("got \(element as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_finishes_loop_when_task_is_cancelled() async {
    let iterated = expectation(description: "The iteration has produced 1 element")
    let finished = expectation(description: "The iteration has finished")

    let base = Indefinite(value: 1).async
    let other = Indefinite(value: "a").async

    let sequence = base.withLatest(from: other)

    let task = Task {
      var iterator = sequence.makeAsyncIterator()

      var firstIteration = false
      var firstElement: (Int, String)?
      while let element = await iterator.next() {
        if !firstIteration {
          firstElement = element
          firstIteration = true
          iterated.fulfill()
        }
      }
      XCTAssertEqual(firstElement!, (1, "a"))
      finished.fulfill()
    }

    // ensure the other task actually starts
    wait(for: [iterated], timeout: 1.0)

    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

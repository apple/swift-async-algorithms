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

final class TestWithLatestFrom2: XCTestCase {
  func test_withLatestFrom_uses_latest_element_from_others() async {
    // Timeline
    // base:      -0-----1      ---2      ---3      ---4      ---5      -x--|
    // other1:    ---a----      ----      -b--      -x--      ----      ----|
    // other2:    -----x--      -y--      ----      ----      -x--      ----|
    // expected:  -------(1,a,x)---(2,a,y)---(3,b,y)---(4,b,y)---(5,b,y)-x--|
    let baseHasProduced0 = expectation(description: "Base has produced 0")

    let other1HasProducedA = expectation(description: "Other has produced 'a'")
    let other1HasProducedB = expectation(description: "Other has produced 'b'")

    let other2HasProducedX = expectation(description: "Other has produced 'x'")
    let other2HasProducedY = expectation(description: "Other has produced 'y'")

    let base = AsyncChannel<Int>()
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let sequence = base.withLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    // expectations that ensure that "others" has really delivered
    // their elements before requesting the next element from "base"
    iterator.onOther1Element = { @Sendable element in
      if element == "a" {
        other1HasProducedA.fulfill()
      }

      if element == "b" {
        other1HasProducedB.fulfill()
      }
    }

    iterator.onOther2Element = { @Sendable element in
      if element == "x" {
        other2HasProducedX.fulfill()
      }

      if element == "y" {
        other2HasProducedY.fulfill()
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
      await other1.send("a")
      wait(for: [other1HasProducedA], timeout: 1.0)
      await other2.send("x")
      wait(for: [other2HasProducedX], timeout: 1.0)
      await base.send(1)
    }

    let element1 = await iterator.next()
    XCTAssertEqual(element1!, (1, "a", "x"))

    Task {
      await other2.send("y")
      wait(for: [other2HasProducedY], timeout: 1.0)
      await base.send(2)
    }

    let element2 = await iterator.next()
    XCTAssertEqual(element2!, (2, "a", "y"))

    Task {
      await other1.send("b")
      wait(for: [other1HasProducedB], timeout: 1.0)
      await base.send(3)
    }

    let element3 = await iterator.next()
    XCTAssertEqual(element3!, (3, "b", "y"))

    Task {
      other1.finish()
      await base.send(4)
    }

    let element4 = await iterator.next()
    XCTAssertEqual(element4!, (4, "b", "y"))

    Task {
      other2.finish()
      await base.send(5)
    }

    let element5 = await iterator.next()
    XCTAssertEqual(element5!, (5, "b", "y"))

    base.finish()

    let element6 = await iterator.next()
    XCTAssertNil(element6)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_throws_when_base_throws_and_pastEnd_is_nil() async throws {
    let base = [1, 2, 3]
    let other1 = Indefinite(value: "a")
    let other2 = Indefinite(value: "x")

    let sequence = base.async.map { try throwOn(1, $0) }.withLatest(from: other1.async, other2.async)
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

  func test_withLatestFrom_throws_when_other1_throws_and_pastEnd_is_nil() async throws {
    let base = Indefinite(value: 1)
    let other1 = AsyncThrowingChannel<String, Error>()
    let other2 = Indefinite(value: "x").async

    let sequence = base.async.withLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    other1.fail(Failure())

    do {
      var element: (Int, String, String)?
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

  func test_withLatestFrom_throws_when_other2_throws_and_pastEnd_is_nil() async throws {
    let base = Indefinite(value: 1)
    let other1 = Indefinite(value: "x").async
    let other2 = AsyncThrowingChannel<String, Error>()

    let sequence = base.async.withLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    other2.fail(Failure())

    do {
      var element: (Int, String, String)?
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
    let other1 = Indefinite(value: "a").async
    let other2 = Indefinite(value: "x").async

    let sequence = base.withLatest(from: other1, other2)

    let task = Task {
      var iterator = sequence.makeAsyncIterator()

      var firstIteration = false
      var firstElement: (Int, String, String)?
      while let element = await iterator.next() {
        if !firstIteration {
          firstElement = element
          firstIteration = true
          iterated.fulfill()
        }
      }
      XCTAssertEqual(firstElement!, (1, "a", "x"))
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

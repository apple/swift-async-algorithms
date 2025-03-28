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

final class TestCombineLatest2: XCTestCase {
  func test_combineLatest() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = combineLatest(a.async, b.async)
    let actual = await Array(sequence)
    XCTAssertGreaterThanOrEqual(actual.count, 3)
  }

  func test_throwing_combineLatest1() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = combineLatest(a.async.map { try throwOn(1, $0) }, b.async)
    var iterator = sequence.makeAsyncIterator()
    do {
      let value = try await iterator.next()
      XCTFail("got \(value as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }

  func test_throwing_combineLatest2() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = combineLatest(a.async, b.async.map { try throwOn("a", $0) })
    var iterator = sequence.makeAsyncIterator()
    do {
      let value = try await iterator.next()
      XCTFail("got \(value as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }

  func test_ordering1() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence(["a", "b", "c"])
    let finished = expectation(description: "finished")
    let sequence = combineLatest(a, b)
    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (2, "b")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (2, "b"), (3, "b")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (2, "b"), (3, "b"), (3, "c")])

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (2, "b"), (3, "b"), (3, "c")])
  }

  func test_ordering2() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence(["a", "b", "c"])
    let finished = expectation(description: "finished")
    let sequence = combineLatest(a, b)
    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (2, "b")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (2, "b"), (2, "c")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (2, "b"), (2, "c"), (3, "c")])

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (2, "b"), (2, "c"), (3, "c")])
  }

  func test_ordering3() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence(["a", "b", "c"])
    let finished = expectation(description: "finished")
    let sequence = combineLatest(a, b)
    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (3, "a")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (3, "a"), (3, "b")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (3, "a"), (3, "b"), (3, "c")])

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (3, "a"), (3, "b"), (3, "c")])
  }

  func test_ordering4() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence(["a", "b", "c"])
    let finished = expectation(description: "finished")
    let sequence = combineLatest(a, b)
    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (1, "c")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (1, "c"), (2, "c")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (1, "c"), (2, "c"), (3, "c")])

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (1, "b"), (1, "c"), (2, "c"), (3, "c")])
  }

  func test_throwing_ordering1() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence(["a", "b", "c"])
    let finished = expectation(description: "finished")
    let sequence = combineLatest(a.map { try throwOn(2, $0) }, b)
    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      do {
        let pastEnd = try await iterator.next()
        XCTAssertNil(pastEnd)
      } catch {
        XCTFail()
      }
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (1, "b")])

    XCTAssertEqual(validator.failure as? Failure, Failure())

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (1, "b")])
  }

  func test_throwing_ordering2() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence(["a", "b", "c"])
    let finished = expectation(description: "finished")
    let sequence = combineLatest(a, b.map { try throwOn("b", $0) })
    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      do {
        let pastEnd = try await iterator.next()
        XCTAssertNil(pastEnd)
      } catch {
        XCTFail()
      }
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a")])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a")])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a")])

    XCTAssertEqual(validator.failure as? Failure, Failure())

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (2, "a")])
  }

  func test_cancellation() async {
    let source1 = Indefinite(value: "test1")
    let source2 = Indefinite(value: "test2")
    let sequence = combineLatest(source1.async, source2.async)
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")
    let task = Task {
      var firstIteration = false
      for await _ in sequence {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }
    // ensure the other task actually starts
    await fulfillment(of: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    await fulfillment(of: [finished], timeout: 1.0)
  }

  func test_combineLatest_when_cancelled() async {
    let t = Task {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      let c1 = Indefinite(value: "test1").async
      let c2 = Indefinite(value: "test1").async
      for await _ in combineLatest(c1, c2) {}
    }
    t.cancel()
  }
}

final class TestCombineLatest3: XCTestCase {
  func test_combineLatest() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [4, 5, 6]
    let sequence = combineLatest(a.async, b.async, c.async)
    let actual = await Array(sequence)
    XCTAssertGreaterThanOrEqual(actual.count, 3)
  }

  func test_ordering1() async {
    var a = GatedSequence([1, 2, 3])
    var b = GatedSequence(["a", "b", "c"])
    var c = GatedSequence([4, 5, 6])
    let finished = expectation(description: "finished")
    let sequence = combineLatest(a, b, c)
    let validator = Validator<(Int, String, Int)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4)])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4)])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4)])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5)])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5)])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5), (3, "c", 5)])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(
      value,
      [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5), (3, "c", 5), (3, "c", 6)]
    )

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(
      value,
      [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5), (3, "c", 5), (3, "c", 6)]
    )
  }
}

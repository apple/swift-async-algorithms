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

final class TestZip2: XCTestCase {
  func test_zip_makes_sequence_equivalent_to_synchronous_zip_when_all_sequences_have_same_size() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]

    let expected = Array(zip(a, b))
    let actual = await Array(zip(a.async, b.async))
    XCTAssertEqual(expected, actual)
  }

  func test_zip_makes_sequence_equivalent_to_synchronous_zip_when_first_is_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]

    let expected = Array(zip(a, b))
    let actual = await Array(zip(a.async, b.async))
    XCTAssertEqual(expected, actual)
  }

  func test_zip_makes_sequence_equivalent_to_synchronous_zip_when_second_is_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]

    let expected = Array(zip(a, b))
    let actual = await Array(zip(a.async, b.async))
    XCTAssertEqual(expected, actual)
  }

  func test_zip_produces_nil_next_element_when_iteration_is_finished_and_all_sequences_have_same_size() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async, b.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = Array(zip(a, b))
    var collected = [(Int, String)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_nil_next_element_when_iteration_is_finished_and_first_is_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async, b.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = Array(zip(a, b))
    var collected = [(Int, String)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_nil_next_element_when_iteration_is_finished_and_second_is_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]
    let sequence = zip(a.async, b.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = Array(zip(a, b))
    var collected = [(Int, String)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_one_element_and_throws_when_first_produces_one_element_and_throws() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async.map { try throwOn(2, $0) }, b.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a")]
    var collected = [(Int, String)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Zipped sequence should throw after one collected element")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_one_element_and_throws_when_second_produces_one_element_and_throws() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async, b.async.map { try throwOn("b", $0) })
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a")]
    var collected = [(Int, String)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Zipped sequence should throw after one collected element")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_finishes_when_iteration_task_is_cancelled() async {
    let source1 = Indefinite(value: "test1")
    let source2 = Indefinite(value: "test2")
    let sequence = zip(source1.async, source2.async)
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

  func test_zip_when_cancelled() async {
    let t = Task {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      let c1 = Indefinite(value: "test1").async
      let c2 = Indefinite(value: "test1").async
      for await _ in zip(c1, c2) {}
    }
    t.cancel()
  }
}

final class TestZip3: XCTestCase {
  func test_zip_makes_sequence_equivalent_to_synchronous_zip_when_all_sequences_have_same_size() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual(expected, actual)
  }

  func test_zip_makes_sequence_equivalent_to_synchronous_zip_when_first_is_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual(expected, actual)
  }

  func test_zip_makes_sequence_equivalent_to_synchronous_zip_when_second_is_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]
    let c = [1, 2, 3]

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual(expected, actual)
  }

  func test_zip_makes_sequence_equivalent_to_synchronous_zip_when_third_is_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3, 4, 5]

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual(expected, actual)
  }

  func test_zip_produces_nil_next_element_when_iteration_is_finished_and_all_sequences_have_same_size() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_nil_next_element_when_iteration_is_finished_and_first_is_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_nil_next_element_when_iteration_is_finished_and_second_is_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_nil_next_element_when_iteration_is_finished_and_third_is_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3, 4, 5]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a", 1), (2, "b", 2), (3, "c", 3)]
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_one_element_and_throws_when_first_produces_one_element_and_throws() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async.map { try throwOn(2, $0) }, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a", 1)]
    var collected = [(Int, String, Int)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Zipped sequence should throw after one collected element")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_one_element_and_throws_when_second_produces_one_element_and_throws() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async.map { try throwOn("b", $0) }, c.async)
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a", 1)]
    var collected = [(Int, String, Int)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Zipped sequence should throw after one collected element")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_produces_one_element_and_throws_when_third_produces_one_element_and_throws() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async.map { try throwOn(2, $0) })
    var iterator = sequence.makeAsyncIterator()

    let expected = [(1, "a", 1)]
    var collected = [(Int, String, Int)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Zipped sequence should throw after one collected element")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_zip_finishes_when_iteration_task_is_cancelled() async {
    let source1 = Indefinite(value: "test1")
    let source2 = Indefinite(value: "test2")
    let source3 = Indefinite(value: "test3")
    let sequence = zip(source1.async, source2.async, source3.async)
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
}

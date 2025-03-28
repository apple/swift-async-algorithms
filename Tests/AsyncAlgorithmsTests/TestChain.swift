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

final class TestChain2: XCTestCase {
  func test_chain2_concatenates_elements_from_sequences_and_returns_nil_when_source_is_pastEnd() async {
    let expected1 = [1, 2, 3]
    let expected2 = [4, 5, 6]
    let expected = expected1 + expected2
    let chained = chain(expected1.async, expected2.async)

    var iterator = chained.makeAsyncIterator()
    var collected = [Int]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_chain2_outputs_elements_from_first_sequence_and_throws_when_first_throws() async throws {
    let chained = chain([1, 2, 3].async.map { try throwOn(3, $0) }, [4, 5, 6].async)
    var iterator = chained.makeAsyncIterator()

    var collected = [Int]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Chained sequence should throw when first sequence throws")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2], collected)

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_chain2_outputs_elements_from_sequences_and_throws_when_second_throws() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async.map { try throwOn(5, $0) })
    var iterator = chained.makeAsyncIterator()

    var collected = [Int]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Chained sequence should throw when second sequence throws")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected, [1, 2, 3, 4])

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_chain2_finishes_when_task_is_cancelled() async {
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let source = Indefinite(value: "test")
    let sequence = chain(source.async, ["past indefinite"].async)

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

final class TestChain3: XCTestCase {
  func test_chain3_concatenates_elements_from_sequences_and_returns_nil_when_source_is_pastEnd() async {
    let expected1 = [1, 2, 3]
    let expected2 = [4, 5, 6]
    let expected3 = [7, 8, 9]
    let expected = expected1 + expected2 + expected3
    let chained = chain(expected1.async, expected2.async, expected3.async)
    var iterator = chained.makeAsyncIterator()

    var collected = [Int]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_chain3_outputs_elements_from_first_sequence_and_throws_when_first_throws() async throws {
    let chained = chain([1, 2, 3].async.map { try throwOn(3, $0) }, [4, 5, 6].async, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()

    var collected = [Int]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Chained sequence should throw when first sequence throws")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected, [1, 2])

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_chain3_outputs_elements_from_sequences_and_throws_when_second_throws() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async.map { try throwOn(5, $0) }, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()

    var collected = [Int]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Chained sequence should throw when second sequence throws")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected, [1, 2, 3, 4])

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_chain3_outputs_elements_from_sequences_and_throws_when_third_throws() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async, [7, 8, 9].async.map { try throwOn(8, $0) })
    var iterator = chained.makeAsyncIterator()

    var collected = [Int]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail("Chained sequence should throw when third sequence throws")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected, [1, 2, 3, 4, 5, 6, 7])

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_chain3_finishes_when_task_is_cancelled() async {
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let source = Indefinite(value: "test")
    let sequence = chain(source.async, ["past indefinite"].async, ["and even further"].async)

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

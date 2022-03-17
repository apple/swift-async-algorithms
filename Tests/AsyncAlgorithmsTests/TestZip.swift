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
import AsyncAlgorithms

final class TestZip2: XCTestCase {
  func test_zip() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let expected = Array(zip(a, b))
    let actual = await Array(zip(a.async, b.async))
    XCTAssertEqual(expected, actual)
  }
  
  func test_zip_first_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]
    let expected = Array(zip(a, b))
    let actual = await Array(zip(a.async, b.async))
    XCTAssertEqual(expected, actual)
  }
  
  func test_zip_second_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]
    let expected = Array(zip(a, b))
    let actual = await Array(zip(a.async, b.async))
    XCTAssertEqual(expected, actual)
  }
  
  func test_iterate_past_end() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async, b.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual([(1, "a"), (2, "b"), (3, "c")], collected)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_iterate_past_end_first_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async, b.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual([(1, "a"), (2, "b"), (3, "c")], collected)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_iterate_past_end_second_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]
    let sequence = zip(a.async, b.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual([(1, "a"), (2, "b"), (3, "c")], collected)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_first_throwing() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async.map { try throwOn(2, $0) }, b.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([(1, "a")], collected)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_second_throwing() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let sequence = zip(a.async, b.async.map { try throwOn("b", $0) })
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([(1, "a")], collected)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_cancellation() async {
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
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

final class TestZip3: XCTestCase {
  func test_zip() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], actual)
  }
  
  func test_zip_first_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], actual)
  }
  
  func test_zip_second_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]
    let c = [1, 2, 3]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], actual)
  }
  
  func test_zip_third_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3, 4, 5]
    let actual = await Array(zip(a.async, b.async, c.async))
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], actual)
  }
  
  func test_iterate_past_end() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], collected)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_iterate_past_end_first_longer() async {
    let a = [1, 2, 3, 4, 5]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], collected)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_iterate_past_end_second_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c", "d", "e"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], collected)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_iterate_past_end_third_longer() async {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3, 4, 5]
    let sequence = zip(a.async, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String, Int)]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual([(1, "a", 1), (2, "b", 2), (3, "c", 3)], collected)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_first_throwing() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async.map { try throwOn(2, $0) }, b.async, c.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String, Int)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([(1, "a", 1)], collected)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_second_throwing() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async.map { try throwOn("b", $0) }, c.async)
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String, Int)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([(1, "a", 1)], collected)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_third_throwing() async throws {
    let a = [1, 2, 3]
    let b = ["a", "b", "c"]
    let c = [1, 2, 3]
    let sequence = zip(a.async, b.async, c.async.map { try throwOn(2, $0) })
    var iterator = sequence.makeAsyncIterator()
    var collected = [(Int, String, Int)]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([(1, "a", 1)], collected)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_cancellation() async {
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
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

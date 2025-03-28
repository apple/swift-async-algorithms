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

final class TestReductions: XCTestCase {
  func test_reductions() async {
    let sequence = [1, 2, 3, 4].async.reductions("") { partial, value in
      partial + "\(value)"
    }
    var iterator = sequence.makeAsyncIterator()
    var collected = [String]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(collected, ["1", "12", "123", "1234"])
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_inclusive_reductions() async {
    let sequence = [1, 2, 3, 4].async.reductions { $0 + $1 }
    var iterator = sequence.makeAsyncIterator()
    var collected = [Int]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(collected, [1, 3, 6, 10])
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throw_upstream_reductions() async throws {
    let sequence = [1, 2, 3, 4].async
      .map { try throwOn(3, $0) }
      .reductions("") { partial, value in
        partial + "\(value)"
      }
    var iterator = sequence.makeAsyncIterator()
    var collected = [String]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    XCTAssertEqual(collected, ["1", "12"])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throw_upstream_inclusive_reductions() async throws {
    let sequence = [1, 2, 3, 4].async
      .map { try throwOn(3, $0) }
      .reductions { $0 + $1 }
    var iterator = sequence.makeAsyncIterator()
    var collected = [Int]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    XCTAssertEqual(collected, [1, 3])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing_reductions() async throws {
    let sequence = [1, 2, 3, 4].async.reductions("") { (partial, value) throws -> String in
      partial + "\(value)"
    }
    var iterator = sequence.makeAsyncIterator()
    var collected = [String]()
    while let item = try await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(collected, ["1", "12", "123", "1234"])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing_inclusive_reductions() async throws {
    let sequence = [1, 2, 3, 4].async.reductions { (lhs, rhs) throws -> Int in
      lhs + rhs
    }
    var iterator = sequence.makeAsyncIterator()
    var collected = [Int]()
    while let item = try await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(collected, [1, 3, 6, 10])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throw_upstream_reductions_throws() async throws {
    let sequence = [1, 2, 3, 4].async
      .map { try throwOn(3, $0) }
      .reductions("") { (partial, value) throws -> String in
        partial + "\(value)"
      }
    var iterator = sequence.makeAsyncIterator()
    var collected = [String]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    XCTAssertEqual(collected, ["1", "12"])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throw_upstream_inclusive_reductions_throws() async throws {
    let sequence = [1, 2, 3, 4].async
      .map { try throwOn(3, $0) }
      .reductions { (lhs, rhs) throws -> Int in
        lhs + rhs
      }
    var iterator = sequence.makeAsyncIterator()
    var collected = [Int]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    XCTAssertEqual(collected, [1, 3])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_reductions_into() async {
    let sequence = [1, 2, 3, 4].async.reductions(into: "") { partial, value in
      partial.append("\(value)")
    }
    var iterator = sequence.makeAsyncIterator()
    var collected = [String]()
    while let item = await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(collected, ["1", "12", "123", "1234"])
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing_reductions_into() async throws {
    let sequence = [1, 2, 3, 4].async.reductions(into: "") { (partial, value) throws -> Void in
      partial.append("\(value)")
    }
    var iterator = sequence.makeAsyncIterator()
    var collected = [String]()
    while let item = try await iterator.next() {
      collected.append(item)
    }
    XCTAssertEqual(collected, ["1", "12", "123", "1234"])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing_reductions_into_throws() async throws {
    let sequence = [1, 2, 3, 4].async.reductions(into: "") { partial, value in
      _ = try throwOn("12", partial)
      partial.append("\(value)")
    }
    var iterator = sequence.makeAsyncIterator()
    var collected = [String]()
    do {
      while let item = try await iterator.next() {
        collected.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
    XCTAssertEqual(collected, ["1", "12"])
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_cancellation() async {
    let source = Indefinite(value: "test")
    let sequence = source.async.reductions(into: "") { partial, value in
      partial = value
    }
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")
    let task = Task {
      var firstIteration = false
      for await el in sequence {
        XCTAssertEqual(el, "test")

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

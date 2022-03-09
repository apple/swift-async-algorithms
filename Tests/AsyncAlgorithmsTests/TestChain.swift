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

final class TestChain2: XCTestCase {
  func test_chain() async {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual([1, 2, 3, 4, 5, 6], actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_first() async throws {
    let chained = chain([1, 2, 3].async.map { try throwOn(3, $0) }, [4, 5, 6].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_second() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async.map { try throwOn(5, $0) })
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2, 3, 4], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_cancellation() async {
    let source = Indefinite(value: "test")
    let sequence = chain(source.async, ["past indefinite"].async)
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

final class TestChain3: XCTestCase {
  func test_chain() async {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8, 9], actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_first() async throws {
    let chained = chain([1, 2, 3].async.map { try throwOn(3, $0) }, [4, 5, 6].async, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_second() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async.map { try throwOn(5, $0) }, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2, 3, 4], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_third() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async, [7, 8, 9].async.map { try throwOn(8, $0) })
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2, 3, 4, 5, 6, 7], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_cancellation() async {
    let source = Indefinite(value: "test")
    let sequence = chain(source.async, ["past indefinite"].async, ["and even further"].async)
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

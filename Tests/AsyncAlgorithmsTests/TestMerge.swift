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

final class TestMerge2: XCTestCase {
  func test_even_values() async {
    let merged = merge([1, 2, 3].async, [4, 5, 6].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6]).sorted()
    XCTAssertEqual(a, b)
  }
  
  func test_longer_first() async {
    let merged = merge([1, 2, 3, 4, 5, 6, 7].async, [8, 9, 10].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]).sorted()
    XCTAssertEqual(a, b)
  }
  
  func test_longer_second() async {
    let merged = merge([1, 2, 3].async, [4, 5, 6, 7].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected)
    let b = Set([1, 2, 3, 4, 5, 6, 7])
    XCTAssertEqual(a, b)
  }
  
  func test_throwing_first() async throws {
    let merged = merge([1, 2, 3, 4, 5].async.map { try throwOn(4, $0) }, [6, 7, 8].async)
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([1, 2, 3]), Set([1, 2, 3]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_longer_second_throwing_first() async throws {
    let merged = merge([1, 2, 3, 4, 5].async.map { try throwOn(4, $0) }, [6, 7, 8, 9, 10, 11].async)
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([1, 2, 3]), Set([1, 2, 3]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_second() async throws {
    let merged = merge([1, 2, 3].async, [4, 5, 6, 7, 8].async.map { try throwOn(7, $0) })
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([4, 5, 6]), Set([4, 5, 6]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_longer_first_throwing_second() async throws {
    let merged = merge([1, 2, 3, 4, 5, 6, 7].async, [7, 8, 9, 10, 11].async.map { try throwOn(10, $0) })
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([7, 8, 9]), Set([7, 8, 9]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_diagram() {
    validate {
      "a-c-e-g-|"
      "-b-d-f-h"
      merge($0.inputs[0], $0.inputs[1])
      "abcdefgh|"
    }
  }
  
  func test_cancellation() async {
    let source1 = Indefinite(value: "test1")
    let source2 = Indefinite(value: "test2")
    let sequence = merge(source1.async, source2.async)
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

final class TestMerge3: XCTestCase {
  func test_even_values() async {
    let merged = merge([1, 2, 3].async, [4, 5, 6].async, [7, 8, 9].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6, 7, 8, 9]).sorted()
    XCTAssertEqual(a, b)
  }

  func test_longer_first() async {
    let merged = merge([1, 2, 3, 4, 5].async, [6, 7, 8].async, [9, 10, 11].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 11]).sorted()
    XCTAssertEqual(a, b)
  }

  func test_longer_second() async {
    let merged = merge([1, 2, 3].async, [4, 5, 6, 7, 8].async, [9, 10, 11].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 11]).sorted()
    XCTAssertEqual(a, b)
  }

  func test_longer_third() async {
    let merged = merge([1, 2, 3].async, [4, 5, 6].async, [7, 8, 9, 10, 11].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 11]).sorted()
    XCTAssertEqual(a, b)
  }

  func test_longer_first_and_third() async {
    let merged = merge([1, 2, 3, 4, 5].async, [6, 7].async, [8, 9, 10, 11].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 11]).sorted()
    XCTAssertEqual(a, b)
  }

  func test_longer_second_and_third() async {
    let merged = merge([1, 2, 3].async, [4, 5, 6, 7].async, [8, 9, 10, 11].async)
    var collected = [Int]()
    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    let a = Set(collected).sorted()
    let b = Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 11]).sorted()
    XCTAssertEqual(a, b)
  }

  func test_throwing_first() async throws {
    let merged = merge([1, 2, 3, 4, 5].async.map { try throwOn(4, $0) }, [6, 7, 8].async, [9, 10, 11].async)
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([1, 2, 3]), Set([1, 2, 3]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_longer_second_throwing_first() async throws {
    let merged = merge([1, 2, 3, 4, 5].async.map { try throwOn(4, $0) }, [6, 7, 8, 9, 10, 11].async, [12, 13, 14].async)
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([1, 2, 3]), Set([1, 2, 3]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing_second() async throws {
    let merged = merge([1, 2, 3].async, [4, 5, 6, 7, 8].async.map { try throwOn(7, $0) }, [9, 10, 11].async)
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([4, 5, 6]), Set([4, 5, 6]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_longer_first_throwing_second() async throws {
    let merged = merge([1, 2, 3, 4, 5, 6, 7].async, [7, 8, 9, 10, 11].async.map { try throwOn(10, $0) }, [12, 13, 14].async)
    var collected = Set<Int>()
    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(collected.intersection([7, 8, 9]), Set([7, 8, 9]))
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_diagram() {
    validate {
      "a---e---|"
      "-b-d-f-h|"
      "--c---g-|"
      merge($0.inputs[0], $0.inputs[1], $0.inputs[2])
      "abcdefgh|"
    }
  }

  func test_cancellation() async {
    let source1 = Indefinite(value: "test1")
    let source2 = Indefinite(value: "test2")
    let source3 = Indefinite(value: "test3")
    let sequence = merge(source1.async, source2.async, source3.async)
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

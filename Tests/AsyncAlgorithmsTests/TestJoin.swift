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

extension Sequence where Element: Sequence, Element.Element: Equatable & Sendable {
  func nestedAsync(throwsOn bad: Element.Element) -> AsyncLazySequence<[AsyncThrowingMapSequence<AsyncLazySequence<Element>,Element.Element>]> {
    let array: [AsyncThrowingMapSequence<AsyncLazySequence<Element>,Element.Element>] = self.map { $0.async }.map {
      $0.map { try throwOn(bad, $0) }
    }
    return array.async
  }
}

extension Sequence where Element: Sequence, Element.Element: Sendable {
  var nestedAsync : AsyncLazySequence<[AsyncLazySequence<Element>]> {
    return self.map { $0.async }.async
  }
}

final class TestJoinedBySeparator: XCTestCase {
  func test_join() async {
    let sequences = [[1, 2, 3], [4, 5, 6], [7, 8, 9]].nestedAsync
    var iterator = sequences.joined(separator: [-1, -2, -3].async).makeAsyncIterator()
    let expected = [1, 2, 3, -1, -2, -3, 4, 5, 6, -1, -2, -3, 7, 8, 9]
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_join_single_sequence() async {
    let sequences = [[1, 2, 3]].nestedAsync
    var iterator = sequences.joined(separator: [-1, -2, -3].async).makeAsyncIterator()
    let expected = [1, 2, 3]
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_join_empty() async {
    let sequences = [AsyncLazySequence<[Int]>]().async
    var iterator = sequences.joined(separator: [-1, -2, -3].async).makeAsyncIterator()
    let expected = [Int]()
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing() async throws {
    let sequences = [[1, 2, 3], [4, 5, 6]].nestedAsync(throwsOn: 5)
    var iterator = sequences.joined(separator: [-1, -2, -3].async).makeAsyncIterator()
    let expected = [1, 2, 3, -1, -2, -3, 4]
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing_separator() async throws {
    let sequences = [[1, 2, 3], [4, 5, 6]].nestedAsync
    let separator = [-1, -2, -3].async.map { try throwOn(-2, $0) }
    var iterator = sequences.joined(separator: separator).makeAsyncIterator()
    let expected = [1, 2, 3, -1]
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_cancellation() async {
    let source : AsyncLazySequence<[AsyncLazySequence<Indefinite<String>>]> = [Indefinite(value: "test").async].async
    let sequence = source.joined(separator: ["past indefinite"].async)
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
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

final class TestJoined: XCTestCase {
  func test_join() async {
    let sequences = [[1, 2, 3], [4, 5, 6], [7, 8, 9]].nestedAsync
    var iterator = sequences.joined().makeAsyncIterator()
    let expected = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_join_single_sequence() async {
    let sequences = [[1, 2, 3]].nestedAsync
    var iterator = sequences.joined().makeAsyncIterator()
    let expected = [1, 2, 3]
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_join_empty() async {
    let sequences = [AsyncLazySequence<[Int]>]().async
    var iterator = sequences.joined().makeAsyncIterator()
    let expected = [Int]()
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_throwing() async throws {
    let sequences = [[1, 2, 3], [4, 5, 6]].nestedAsync(throwsOn: 5)
    var iterator = sequences.joined().makeAsyncIterator()
    let expected = [1, 2, 3, 4]
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual(expected, actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_cancellation() async {
    let source : AsyncLazySequence<[AsyncLazySequence<Indefinite<String>>]> = [Indefinite(value: "test").async].async
    let sequence = source.joined()
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
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

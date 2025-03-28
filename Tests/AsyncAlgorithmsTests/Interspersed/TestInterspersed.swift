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

import AsyncAlgorithms
import XCTest

final class TestInterspersed: XCTestCase {
  func test_interspersed() async {
    let source = [1, 2, 3, 4, 5]
    let expected = [1, 0, 2, 0, 3, 0, 4, 0, 5]
    let sequence = source.async.interspersed(with: 0)
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_every() async {
    let source = [1, 2, 3, 4, 5, 6, 7, 8]
    let expected = [1, 2, 3, 0, 4, 5, 6, 0, 7, 8]
    let sequence = source.async.interspersed(every: 3, with: 0)
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_closure() async {
    let source = [1, 2, 3, 4, 5]
    let expected = [1, 0, 2, 0, 3, 0, 4, 0, 5]
    let sequence = source.async.interspersed(with: { 0 })
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_async_closure() async {
    let source = [1, 2, 3, 4, 5]
    let expected = [1, 0, 2, 0, 3, 0, 4, 0, 5]
    let sequence = source.async.interspersed {
      try! await Task.sleep(nanoseconds: 1000)
      return 0
    }
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_throwing_closure() async {
    let source = [1, 2]
    let expected = [1]
    var actual = [Int]()
    let sequence = source.async.interspersed(with: { throw Failure() })

    var iterator = sequence.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try! await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_async_throwing_closure() async {
    let source = [1, 2]
    let expected = [1]
    var actual = [Int]()
    let sequence = source.async.interspersed {
      try await Task.sleep(nanoseconds: 1000)
      throw Failure()
    }

    var iterator = sequence.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try! await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_empty() async {
    let source = [Int]()
    let expected = [Int]()
    let sequence = source.async.interspersed(with: 0)
    var actual = [Int]()
    var iterator = sequence.makeAsyncIterator()
    while let item = await iterator.next() {
      actual.append(item)
    }
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_interspersed_with_throwing_upstream() async {
    let source = [1, 2, 3, -1, 4, 5]
    let expected = [1, 0, 2, 0, 3]
    var actual = [Int]()
    let sequence = source.async.map {
      try throwOn(-1, $0)
    }.interspersed(with: 0)

    var iterator = sequence.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try! await iterator.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(actual, expected)
  }

  func test_cancellation() async {
    let source = Indefinite(value: "test")
    let sequence = source.async.interspersed(with: "sep")
    let lockStepChannel = AsyncChannel<Void>()

    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        var iterator = sequence.makeAsyncIterator()
        let _ = await iterator.next()

        // Information the parent task that we are consuming
        await lockStepChannel.send(())

        while let _ = await iterator.next() {}

        await lockStepChannel.send(())
      }

      // Waiting until the child task started consuming
      _ = await lockStepChannel.first { _ in true }

      // Now we cancel the child
      group.cancelAll()

      await group.waitForAll()
    }
  }
}

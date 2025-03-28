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

final class TestBufferedByteIterator: XCTestCase {
  actor Isolated<T: Sendable> {
    var value: T

    init(_ value: T) {
      self.value = value
    }

    func update(_ value: T) async {
      self.value = value
    }
  }

  func test_immediately_empty() async throws {
    let reloaded = Isolated(false)
    var iterator = AsyncBufferedByteIterator(capacity: 3) { buffer in
      XCTAssertEqual(buffer.count, 3)
      await reloaded.update(true)
      return 0
    }
    var wasReloaded = await reloaded.value
    XCTAssertFalse(wasReloaded)
    let byte = try await iterator.next()
    XCTAssertNil(byte)
    wasReloaded = await reloaded.value
    XCTAssertTrue(wasReloaded)
  }

  func test_one_pass() async throws {
    let reloaded = Isolated(0)
    var iterator = AsyncBufferedByteIterator(capacity: 3) { buffer in
      XCTAssertEqual(buffer.count, 3)
      let count = await reloaded.value
      await reloaded.update(count + 1)
      if count >= 1 {
        return 0
      }
      buffer.copyBytes(from: [1, 2, 3])
      return 3
    }

    var reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 0)
    var byte = try await iterator.next()
    XCTAssertEqual(byte, 1)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 1)
    byte = try await iterator.next()
    XCTAssertEqual(byte, 2)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 1)
    byte = try await iterator.next()
    XCTAssertEqual(byte, 3)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 1)
    byte = try await iterator.next()
    XCTAssertNil(byte)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 2)
    byte = try await iterator.next()
    XCTAssertNil(byte)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 2)
  }

  func test_three_pass() async throws {
    let reloaded = Isolated(0)
    var iterator = AsyncBufferedByteIterator(capacity: 3) { buffer in
      XCTAssertEqual(buffer.count, 3)
      let count = await reloaded.value
      await reloaded.update(count + 1)
      if count >= 3 {
        return 0
      }
      buffer.copyBytes(from: [1, 2, 3])
      return 3
    }

    var reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 0)

    for n in 1...3 {
      var byte = try await iterator.next()
      XCTAssertEqual(byte, 1)
      reloadCount = await reloaded.value
      XCTAssertEqual(reloadCount, n)
      byte = try await iterator.next()
      XCTAssertEqual(byte, 2)
      reloadCount = await reloaded.value
      XCTAssertEqual(reloadCount, n)
      byte = try await iterator.next()
      XCTAssertEqual(byte, 3)
      reloadCount = await reloaded.value
      XCTAssertEqual(reloadCount, n)
    }

    var byte = try await iterator.next()
    XCTAssertNil(byte)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 4)
    byte = try await iterator.next()
    XCTAssertNil(byte)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 4)
  }

  func test_three_pass_throwing() async throws {
    let reloaded = Isolated(0)
    var iterator = AsyncBufferedByteIterator(capacity: 3) { buffer in
      XCTAssertEqual(buffer.count, 3)
      let count = await reloaded.value
      await reloaded.update(count + 1)
      if count >= 3 {
        return 0
      }
      if count == 2 {
        throw Failure()
      }
      buffer.copyBytes(from: [1, 2, 3])
      return 3
    }

    var reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 0)

    for n in 1...3 {
      do {
        var byte = try await iterator.next()
        XCTAssertEqual(byte, 1)
        reloadCount = await reloaded.value
        XCTAssertEqual(reloadCount, n)
        byte = try await iterator.next()
        XCTAssertEqual(byte, 2)
        reloadCount = await reloaded.value
        XCTAssertEqual(reloadCount, n)
        byte = try await iterator.next()
        XCTAssertEqual(byte, 3)
        reloadCount = await reloaded.value
        XCTAssertEqual(reloadCount, n)
      } catch {
        XCTAssertEqual(n, 3)
        break
      }

    }

    var byte = try await iterator.next()
    XCTAssertNil(byte)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 3)
    byte = try await iterator.next()
    XCTAssertNil(byte)
    reloadCount = await reloaded.value
    XCTAssertEqual(reloadCount, 3)
  }

  func test_cancellation() async {
    struct RepeatingBytes: AsyncSequence {
      typealias Element = UInt8

      func makeAsyncIterator() -> AsyncBufferedByteIterator {
        AsyncBufferedByteIterator(capacity: 3) { buffer in
          buffer.copyBytes(from: [1, 2, 3])
          return 3
        }
      }
    }
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")
    let task = Task {
      var firstIteration = false
      do {
        for try await _ in RepeatingBytes() {
          if !firstIteration {
            iterated.fulfill()
            firstIteration = true
          }
        }
        XCTFail("expected to throw a cancellation error")
      } catch {
        if error is CancellationError {
          finished.fulfill()
        }
      }
    }
    await fulfillment(of: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    await fulfillment(of: [finished], timeout: 1.0)
  }
}

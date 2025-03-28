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

final class TestThrowingChannel: XCTestCase {
  func test_asyncThrowingChannel_delivers_elements_when_several_producers_and_several_consumers() async throws {
    let sents = (1...10)
    let expected = Set(sents)

    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // When: sending elements from tasks in a group
    Task {
      await withTaskGroup(of: Void.self) { group in
        for sent in sents {
          group.addTask {
            await sut.send(sent)
          }
        }
      }
    }

    // When: receiving those elements from tasks in a group
    let collected = try await withThrowingTaskGroup(of: Int.self, returning: Set<Int>.self) { group in
      for _ in sents {
        group.addTask {
          var iterator = sut.makeAsyncIterator()
          let received = try await iterator.next()
          return received!
        }
      }

      var collected = Set<Int>()
      for try await element in group {
        collected.update(with: element)
      }
      return collected
    }

    // Then: all elements are sent and received
    XCTAssertEqual(collected, expected)
  }

  func test_asyncThrowingChannel_resumes_producers_and_discards_additional_elements_when_finish_is_called()
    async throws
  {
    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // Given: 2 suspended send operations
    let task1 = Task {
      await sut.send(1)
    }

    let task2 = Task {
      await sut.send(2)
    }

    // When: finishing the channel
    sut.finish()

    // Then: the send operations are resumed
    _ = await (task1.value, task2.value)

    // When: sending an extra value
    await sut.send(3)

    // Then: the operation and the iteration are immediately resumed
    var collected = [Int]()
    for try await element in sut {
      collected.append(element)
    }
    XCTAssertTrue(collected.isEmpty)
  }

  func test_asyncThrowingChannel_resumes_producers_and_discards_additional_elements_when_fail_is_called() async throws {
    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // Given: 2 suspended send operations
    let task1 = Task {
      await sut.send(1)
    }

    let task2 = Task {
      await sut.send(2)
    }

    // When: failing the channel
    sut.fail(Failure())

    // Then: the send operations are resumed
    _ = await (task1.value, task2.value)

    // When: sending an extra value
    await sut.send(3)

    // Then: the send operation is resumed
    // Then: the iteration is resumed with a failure
    var collected = [Int]()
    do {
      for try await element in sut {
        collected.append(element)
      }
    } catch {
      XCTAssertTrue(collected.isEmpty)
      XCTAssertEqual(error as? Failure, Failure())
    }

    // When: requesting a next value
    var iterator = sut.makeAsyncIterator()
    let pastFailure = try await iterator.next()

    // Then: the past failure is nil
    XCTAssertNil(pastFailure)
  }

  func test_asyncThrowingChannel_resumes_consumers_when_finish_is_called() async throws {
    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // Given: 2 suspended iterations
    let task1 = Task<Int?, Error> {
      var iterator = sut.makeAsyncIterator()
      return try await iterator.next()
    }

    let task2 = Task<Int?, Error> {
      var iterator = sut.makeAsyncIterator()
      return try await iterator.next()
    }

    // When: finishing the channel
    sut.finish()

    // Then: the iterations are resumed with nil values
    let (collected1, collected2) = try await (task1.value, task2.value)
    XCTAssertNil(collected1)
    XCTAssertNil(collected2)

    // When: requesting a next value
    var iterator = sut.makeAsyncIterator()
    let pastEnd = try await iterator.next()

    // Then: the past end is nil
    XCTAssertNil(pastEnd)
  }

  func test_asyncThrowingChannel_resumes_consumer_when_fail_is_called() async throws {
    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // Given: suspended iteration
    let task = Task<Int?, Error> {
      var iterator = sut.makeAsyncIterator()

      do {
        _ = try await iterator.next()
        XCTFail("We expect the above call to throw")
      } catch {
        XCTAssertEqual(error as? Failure, Failure())
      }

      return try await iterator.next()
    }

    // When: failing the channel
    sut.fail(Failure())

    // Then: the iterations are resumed with the error and the next element is nil
    do {
      let collected = try await task.value
      XCTAssertNil(collected)
    } catch {
      XCTFail("The task should not fail, the past failure element should be nil, not a failure.")
    }
  }

  func test_asyncThrowingChannel_resumes_consumers_when_fail_is_called() async throws {
    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // Given: 2 suspended iterations
    let task1 = Task<Int?, Error> {
      var iterator = sut.makeAsyncIterator()
      return try await iterator.next()
    }

    let task2 = Task<Int?, Error> {
      var iterator = sut.makeAsyncIterator()
      return try await iterator.next()
    }

    // When: failing the channel
    sut.fail(Failure())

    // Then: the iterations are resumed with the error
    do {
      _ = try await task1.value
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }

    do {
      _ = try await task2.value
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }

    // When: requesting a next value
    var iterator = sut.makeAsyncIterator()
    let pastFailure = try await iterator.next()

    // Then: the past failure is nil
    XCTAssertNil(pastFailure)
  }

  func test_asyncThrowingChannel_resumes_consumer_with_error_when_already_failed() async throws {
    // Given: an AsyncThrowingChannel that is failed
    let sut = AsyncThrowingChannel<Int, Error>()
    sut.fail(Failure())

    var iterator = sut.makeAsyncIterator()

    // When: requesting the next element
    do {
      _ = try await iterator.next()
    } catch {
      // Then: the iteration is resumed with the error
      XCTAssertEqual(error as? Failure, Failure())
    }

    // When: requesting the next element past failure
    do {
      let pastFailure = try await iterator.next()
      // Then: the past failure is nil
      XCTAssertNil(pastFailure)
    } catch {
      XCTFail("The past failure should not throw")
    }
  }

  func test_asyncThrowingChannel_resumes_producer_when_task_is_cancelled() async throws {
    let send1IsResumed = expectation(description: "The first send operation is resumed")

    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // Given: 2 suspended send operations
    let task1 = Task {
      await sut.send(1)
      send1IsResumed.fulfill()
    }

    let task2 = Task {
      await sut.send(2)
    }

    // When: cancelling the first task
    task1.cancel()

    // Then: the first sending operation is resumed
    await fulfillment(of: [send1IsResumed], timeout: 1.0)

    // When: collecting elements
    var iterator = sut.makeAsyncIterator()
    let collected = try await iterator.next()

    // Then: the second operation resumes and the iteration receives the element
    _ = await task2.value
    XCTAssertEqual(collected, 2)
  }

  func test_asyncThrowingChannel_resumes_consumer_when_task_is_cancelled() async throws {
    // Given: an AsyncThrowingChannel
    let sut = AsyncThrowingChannel<Int, Error>()

    // Given: 2 suspended iterations
    let task1 = Task<Int?, Error> {
      var iterator = sut.makeAsyncIterator()
      return try await iterator.next()
    }

    let task2 = Task<Int?, Error> {
      var iterator = sut.makeAsyncIterator()
      return try await iterator.next()
    }

    // When: cancelling the first task
    task1.cancel()

    // Then: the first iteration is resumed with a nil element
    let collected1 = try await task1.value
    XCTAssertNil(collected1)

    // When: sending an element
    await sut.send(1)

    // Then: the second iteration is resumed with the element
    let collected2 = try await task2.value
    XCTAssertEqual(collected2, 1)
  }
}

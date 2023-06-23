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

final class TestChannel: XCTestCase {
  func test_asyncChannel_delivers_elements_when_several_producers_and_several_consumers() async {
    let sents = (1...10)
    let expected = Set(sents)

    // Given: an AsyncChannel
    let sut = AsyncChannel<Int>()

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
    let collected = await withTaskGroup(of: Int.self, returning: Set<Int>.self) { group in
      for _ in sents {
        group.addTask {
          var iterator = sut.makeAsyncIterator()
          let received = await iterator.next()
          return received!
        }
      }

      var collected = Set<Int>()
      for await element in group {
        collected.update(with: element)
      }
      return collected
    }

    // Then: all elements are sent and received
    XCTAssertEqual(collected, expected)
  }

  func test_asyncChannel_resumes_producers_and_discards_additional_elements_when_finish_is_called() async {
    // Given: an AsyncChannel
    let sut = AsyncChannel<Int>()

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
    for await element in sut {
      collected.append(element)
    }
    XCTAssertTrue(collected.isEmpty)
  }

  func test_asyncChannel_resumes_consumers_when_finish_is_called() async {
    // Given: an AsyncChannel
    let sut = AsyncChannel<Int>()

    // Given: 2 suspended iterations
    let task1 = Task<Int?, Never> {
      var iterator = sut.makeAsyncIterator()
      return await iterator.next()
    }

    let task2 = Task<Int?, Never> {
      var iterator = sut.makeAsyncIterator()
      return await iterator.next()
    }

    // When: finishing the channel
    sut.finish()

    // Then: the iterations are resumed with nil values
    let (collected1, collected2) = await (task1.value, task2.value)
    XCTAssertNil(collected1)
    XCTAssertNil(collected2)

    // When: requesting a next value
    var iterator = sut.makeAsyncIterator()
    let pastEnd = await iterator.next()

    // Then: the past end is nil
    XCTAssertNil(pastEnd)
  }

  func test_asyncChannel_resumes_producer_when_task_is_cancelled() async {
    let send1IsResumed = expectation(description: "The first send operation is resumed")

    // Given: an AsyncChannel
    let sut = AsyncChannel<Int>()

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
    let collected = await iterator.next()

    // Then: the second operation resumes and the iteration receives the element
    _ = await task2.value
    XCTAssertEqual(collected, 2)
  }

  func test_asyncChannel_resumes_consumer_when_task_is_cancelled() async {
    // Given: an AsyncChannel
    let sut = AsyncChannel<Int>()

    // Given: 2 suspended iterations
    let task1 = Task<Int?, Never> {
      var iterator = sut.makeAsyncIterator()
      return await iterator.next()
    }

    let task2 = Task<Int?, Never> {
      var iterator = sut.makeAsyncIterator()
      return await iterator.next()
    }

    // When: cancelling the first task
    task1.cancel()

    // Then: the iteration is resumed with a nil element
    let collected1 = await task1.value
    XCTAssertNil(collected1)

    // When: sending an element
    await sut.send(1)

    // Then: the second iteration is resumed with the element
    let collected2 = await task2.value
    XCTAssertEqual(collected2, 1)
  }
}

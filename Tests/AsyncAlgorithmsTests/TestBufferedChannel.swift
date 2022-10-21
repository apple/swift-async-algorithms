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
@testable import AsyncAlgorithms

final class TestBufferedChannel: XCTestCase {
  func test_asyncBufferedChannel_sends_elements_without_suspending_when_buffer_is_available() async {
    let sents = (1...10)
    let expected = Set(sents)
    var collected = Set<Int>()

    let channel = AsyncBufferedChannel<Int>(bufferSize: UInt(sents.count))

    for sent in sents {
      await channel.send(sent)
    }

    var iterator = channel.makeAsyncIterator()
    for _ in sents {
      let received = await iterator.next()
      collected.update(with: received!)
    }

    XCTAssertEqual(collected, expected)
  }

  func test_asyncBufferedChannel_send_suspends_when_buffer_is_full() async {
    let expected = [1, 2]
    let hasSuspended = expectation(description: "The send operation has suspended")
    let hasResumed = expectation(description: "The send operation has resumed")

    let channel = AsyncBufferedChannel<Int>(bufferSize: 1)
    channel.onSendSuspended = {
      hasSuspended.fulfill()
    }

    var iterator = channel.makeAsyncIterator()

    await channel.send(1)
    // the buffer is now full

    Task {
      await channel.send(2)
      hasResumed.fulfill()
    }

    wait(for: [hasSuspended], timeout: 1.0)
    // the 2nd sending operation is suspended

    let collected1 = await iterator.next()
    // a slot is now free in the buffer, the 2nd sending operation is resumed and the element is buffered
    wait(for: [hasResumed], timeout: 1.0)

    let collected2 = await iterator.next()
    XCTAssertEqual([collected1, collected2], expected)
  }

  func test_asyncBufferedChannel_send_resumes_suspended_consumers() async {
    let hasSuspended = expectation(description: "The next has suspended")

    let channel = AsyncBufferedChannel<Int>(bufferSize: 1)
    channel.onNextSuspended = {
      hasSuspended.fulfill()
    }

    let task = Task {
      var iterator = channel.makeAsyncIterator()
      let received = await iterator.next()
      return received
    }

    wait(for: [hasSuspended], timeout: 1.0)
    // the next has suspended

    await channel.send(1)

    let received1 = await task.value
    XCTAssertEqual(received1, 1)

    // the buffer is still available
    await channel.send(2)
    var iterator = channel.makeAsyncIterator()
    let received2 = await iterator.next()

    XCTAssertEqual(received2, 2)
  }

  func test_asyncBufferedChannel_sends_and_consumes_values_when_several_producers_and_consumers() async {
    let sents = (1...10)
    let expected = Set(sents)

    let channel = AsyncBufferedChannel<Int>(bufferSize: 1)

    // concurrent producers
    for sent in sents {
      Task {
        await channel.send(sent)
      }
    }

    // concurrent consumers
    let collected = await withTaskGroup(of: Int.self, returning: Set<Int>.self) { group in
      for _ in sents {
        group.addTask {
          var iterator = channel.makeAsyncIterator()
          let value = await iterator.next()
          return value!
        }
      }

      var collected = Set<Int>()
      for await received in group {
        collected.update(with: received)
      }
      return collected
    }

    XCTAssertEqual(collected, expected)
  }

  func test_asyncBufferedChannel_finish_allows_to_flush_the_buffer_and_suspended_send_operations() async {
    let expected = [1, 2, 3, 4, 5, 6]
    let hasSuspended = expectation(description: "The send operation has suspended")

    let channel = AsyncBufferedChannel<Int>(bufferSize: 5)
    channel.onSendSuspended = {
      hasSuspended.fulfill()
    }

    await channel.send(1)
    await channel.send(2)
    await channel.send(3)
    await channel.send(4)
    await channel.send(5)
    // the buffer is now full

    Task {
      await channel.send(6)
    }

    wait(for: [hasSuspended], timeout: 1.0)
    // the 6th sending operation is suspended

    channel.finish()

    var collected = [Int]()
    for await element in channel {
      collected.append(element)
    }

    // all the elements (buffered + suspended) are collected
    XCTAssertEqual(collected, expected)

    // the sending operation is not suspended
    await channel.send(7)

    // the consumer receives nil
    var iterator = channel.makeAsyncIterator()
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)

  }

  func test_asyncBufferedChannel_finish_resumes_suspended_consumers() async {
    let hasSuspended = expectation(description: "The next has suspended")
    hasSuspended.expectedFulfillmentCount = 2

    let channel = AsyncBufferedChannel<Int>(bufferSize: 1)
    channel.onNextSuspended = {
      hasSuspended.fulfill()
    }

    let task1 = Task {
      var collected = [Int]()
      for await element in channel {
        collected.append(element)
      }
      XCTAssertTrue(collected.isEmpty)
    }

    let task2 = Task {
      var collected = [Int]()
      for await element in channel {
        collected.append(element)
      }
      XCTAssertTrue(collected.isEmpty)
    }

    wait(for: [hasSuspended], timeout: 1.0)
    // the 2 consumers have suspended

    channel.finish()

    var collected = [Int]()
    for await element in channel {
      collected.append(element)
    }

    _ = await (task1.value, task2.value)

    // the sending operations are not suspended
    await channel.send(1)
    await channel.send(2)

    // the consumer receives nil
    var iterator = channel.makeAsyncIterator()
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_asyncBufferedChannel_resumes_suspended_send_when_task_is_cancelled() async {
    let hasSuspended = expectation(description: "The send operations have suspended")
    hasSuspended.expectedFulfillmentCount = 2

    let channel = AsyncBufferedChannel<Int>(bufferSize: 1)
    channel.onSendSuspended = {
      hasSuspended.fulfill()
    }

    await channel.send(1)
    // the buffer is now full

    let task1 = Task {
      await channel.send(2)
    }

    let task2 = Task {
      await channel.send(3)
    }

    wait(for: [hasSuspended], timeout: 1.0)
    // the send operations have suspended

    task1.cancel()

    _ = await task1.value
    // the send operation has resumed

    var iterator = channel.makeAsyncIterator()
    let collected1 = await iterator.next()
    let collected2 = await iterator.next()

    _ = await task2.value
    // all the elements have been collected

    // the buffered value is collected
    XCTAssertEqual([collected1, collected2], [1, 3])
  }

  func test_asyncBufferedChannel_resumes_suspended_consumers_when_task_is_cancelled() async {
    let hasSuspended = expectation(description: "The nexts have suspended")
    hasSuspended.expectedFulfillmentCount = 2

    let channel = AsyncBufferedChannel<Int>(bufferSize: 1)
    channel.onNextSuspended = {
      hasSuspended.fulfill()
    }

    let task1 = Task {
      var collected = [Int]()
      for await element in channel {
        collected.append(element)
      }
      XCTAssertTrue(collected.isEmpty)
    }

    let task2 = Task {
      var collected = [Int]()
      for await element in channel {
        collected.append(element)
      }
      XCTAssertTrue(collected.isEmpty)
    }

    wait(for: [hasSuspended], timeout: 1.0)
    // the next are suspended

    task1.cancel()
    task2.cancel()

    _ = await (task1.value, task2.value)
    // the next have resumed
  }
}

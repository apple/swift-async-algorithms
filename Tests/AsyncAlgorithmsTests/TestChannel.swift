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

final class TestChannel: XCTestCase {
  func test_asyncChannel_delivers_values_when_two_producers_and_two_consumers() async {
    let (sentFromProducer1, sentFromProducer2) = ("test1", "test2")
    let expected = Set([sentFromProducer1, sentFromProducer2])

    let channel = AsyncChannel<String>()
    Task {
      await channel.send(sentFromProducer1)
    }
    Task {
      await channel.send(sentFromProducer2)
    }
    
    let t: Task<String?, Never> = Task {
      var iterator = channel.makeAsyncIterator()
      let value = await iterator.next()
      return value
    }
    var iterator = channel.makeAsyncIterator()

    let (collectedFromConsumer1, collectedFromConsumer2) = (await t.value, await iterator.next())
    let collected = Set([collectedFromConsumer1, collectedFromConsumer2])

    XCTAssertEqual(collected, expected)
  }
  
  func test_asyncThrowingChannel_delivers_values_when_two_producers_and_two_consumers() async throws {
    let (sentFromProducer1, sentFromProducer2) = ("test1", "test2")
    let expected = Set([sentFromProducer1, sentFromProducer2])

    let channel = AsyncThrowingChannel<String, Error>()
    Task {
      await channel.send("test1")
    }
    Task {
      await channel.send("test2")
    }
    
    let t: Task<String?, Error> = Task {
      var iterator = channel.makeAsyncIterator()
      let value = try await iterator.next()
      return value
    }
    var iterator = channel.makeAsyncIterator()

    let (collectedFromConsumer1, collectedFromConsumer2) = (try await t.value, try await iterator.next())
    let collected = Set([collectedFromConsumer1, collectedFromConsumer2])
    
    XCTAssertEqual(collected, expected)
  }
  
  func test_asyncThrowingChannel_throws_and_discards_additional_sent_values_when_fail_is_called() async {
    let sendImmediatelyResumes = expectation(description: "Send immediately resumes after fail")

    let channel = AsyncThrowingChannel<String, Error>()
    channel.fail(Failure())

    var iterator = channel.makeAsyncIterator()
    do {
      let _ = try await iterator.next()
      XCTFail("The AsyncThrowingChannel should have thrown")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }

    do {
      let pastFailure = try await iterator.next()
      XCTAssertNil(pastFailure)
    } catch {
      XCTFail("The AsyncThrowingChannel should not fail when failure has already been fired")
    }

    await channel.send("send")
    sendImmediatelyResumes.fulfill()
    wait(for: [sendImmediatelyResumes], timeout: 1.0)
  }

  func test_asyncChannel_ends_alls_iterators_and_discards_additional_sent_values_when_finish_is_called() async throws {
    let channel = AsyncChannel<String>()
    let complete = ManagedCriticalState(false)
    let finished = AsyncExpectation.expectation(description: "finished")

    Task {
      channel.finish()
      complete.withCriticalRegion { $0 = true }
      await finished.fulfill()
    }

    let valueFromConsumer1 = ManagedCriticalState<String?>(nil)
    let valueFromConsumer2 = ManagedCriticalState<String?>(nil)

    let received = AsyncExpectation.expectation(description: "received", expectedFulfillmentCount: 2)

    let pastEnd = AsyncExpectation.expectation(description: "pastEnd", expectedFulfillmentCount: 2)

    Task {
      var iterator = channel.makeAsyncIterator()
      let ending = await iterator.next()
      valueFromConsumer1.withCriticalRegion { $0 = ending }
      await received.fulfill()
      let item = await iterator.next()
      XCTAssertNil(item)
      await pastEnd.fulfill()
    }

    Task {
      var iterator = channel.makeAsyncIterator()
      let ending = await iterator.next()
      valueFromConsumer2.withCriticalRegion { $0 = ending }
      await received.fulfill()
      let item = await iterator.next()
      XCTAssertNil(item)
      await pastEnd.fulfill()
    }
    
    try await AsyncExpectation.waitForExpectations([finished, received], timeout: 1.0)

    XCTAssertTrue(complete.withCriticalRegion { $0 })
    XCTAssertEqual(valueFromConsumer1.withCriticalRegion { $0 }, nil)
    XCTAssertEqual(valueFromConsumer2.withCriticalRegion { $0 }, nil)

    try await AsyncExpectation.waitForExpectations([pastEnd], timeout: 1.0)
    let additionalSend = AsyncExpectation.expectation(description: "additional send")
    Task {
      await channel.send("test")
      await additionalSend.fulfill()
    }
    try await AsyncExpectation.waitForExpectations([additionalSend], timeout: 1.0)
  }
  
  func test_asyncThrowingChannel_ends_alls_iterators_and_discards_additional_sent_values_when_finish_is_called() async throws {
    let channel = AsyncThrowingChannel<String, Error>()
    let complete = ManagedCriticalState(false)
    let finished = AsyncExpectation.expectation(description: "finished")
    
    Task {
      channel.finish()
      complete.withCriticalRegion { $0 = true }
      await finished.fulfill()
    }

    let valueFromConsumer1 = ManagedCriticalState<String?>(nil)
    let valueFromConsumer2 = ManagedCriticalState<String?>(nil)

    let received = AsyncExpectation.expectation(description: "received", expectedFulfillmentCount: 2)

    let pastEnd = AsyncExpectation.expectation(description: "pastEnd", expectedFulfillmentCount: 2)

    Task {
      var iterator = channel.makeAsyncIterator()
      let ending = try await iterator.next()
      valueFromConsumer1.withCriticalRegion { $0 = ending }
      await received.fulfill()
      let item = try await iterator.next()
      XCTAssertNil(item)
      await pastEnd.fulfill()
    }

    Task {
      var iterator = channel.makeAsyncIterator()
      let ending = try await iterator.next()
      valueFromConsumer2.withCriticalRegion { $0 = ending }
      await received.fulfill()
      let item = try await iterator.next()
      XCTAssertNil(item)
      await pastEnd.fulfill()
    }
    
    try await AsyncExpectation.waitForExpectations([finished, received], timeout: 1.0)

    XCTAssertTrue(complete.withCriticalRegion { $0 })
    XCTAssertEqual(valueFromConsumer1.withCriticalRegion { $0 }, nil)
    XCTAssertEqual(valueFromConsumer2.withCriticalRegion { $0 }, nil)

    try await AsyncExpectation.waitForExpectations([pastEnd], timeout: 1.0)
    let additionalSend = AsyncExpectation.expectation(description: "additional send")
    Task {
      await channel.send("test")
      await additionalSend.fulfill()
    }
    try await AsyncExpectation.waitForExpectations([additionalSend], timeout: 1.0)
  }
  
  func test_asyncChannel_ends_iterator_when_task_is_cancelled() async {
    let channel = AsyncChannel<String>()
    let ready = expectation(description: "ready")
    let task: Task<String?, Never> = Task {
      var iterator = channel.makeAsyncIterator()
      ready.fulfill()
      return await iterator.next()
    }
    await waitForExpectations(timeout: 1.0)
    task.cancel()
    let done = expectation(description: "done")
    Task {
      let value = await task.value
      XCTAssertNil(value)
      done.fulfill()
    }
    await waitForExpectations(timeout: 1.0)
  }

  func test_asyncThrowingChannel_ends_iterator_when_task_is_cancelled() async throws {
    let channel = AsyncThrowingChannel<String, Error>()
    let ready = expectation(description: "ready")
    let task: Task<String?, Error> = Task {
      var iterator = channel.makeAsyncIterator()
      ready.fulfill()
      return try await iterator.next()
    }
    await waitForExpectations(timeout: 1.0)
    task.cancel()
    let done = expectation(description: "done")
    Task {
      let value = try await task.value
      XCTAssertNil(value)
      done.fulfill()
    }
    await waitForExpectations(timeout: 1.0)
  }
  
  func test_asyncChannel_resumes_send_when_task_is_cancelled() async {
    let channel = AsyncChannel<Int>()
    let notYetDone = expectation(description: "not yet done")
    notYetDone.isInverted = true
    let task = Task {
      await channel.send(1)
      notYetDone.fulfill()
    }
    await waitForExpectations(timeout: 0.1)
    task.cancel()
    let done = expectation(description: "done")
    Task {
        _ = await task.value
        done.fulfill()
    }
    await waitForExpectations(timeout: 1.0)
  }
  
  func test_asyncThrowingChannel_resumes_send_when_task_is_cancelled() async {
    let channel = AsyncThrowingChannel<Int, Error>()
    let notYetDone = expectation(description: "not yet done")
    notYetDone.isInverted = true
    let task = Task {
      await channel.send(1)
      notYetDone.fulfill()
    }
    await waitForExpectations(timeout: 0.1)
    task.cancel()
    let done = expectation(description: "done")
    Task {
        _ = await task.value
        done.fulfill()
    }
    await waitForExpectations(timeout: 1.0)
  }
}

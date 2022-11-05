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

final class TestSubject: XCTestCase {
  func test_asyncSubject_delivers_values_when_two_producers_and_two_consumers() async {
    let (sentFromProducer1, sentFromProducer2) = ("test1", "test2")
    let expected = Set([sentFromProducer1, sentFromProducer2])

    let subject = AsyncSubject<String>()
    Task {
      subject.send(sentFromProducer1)
    }
    Task {
      subject.send(sentFromProducer2)
    }
    
    let t: Task<String?, Never> = Task {
      var iterator = subject.makeAsyncIterator()
      let value = await iterator.next()
      return value
    }
    var iterator = subject.makeAsyncIterator()

    let (collectedFromConsumer1, collectedFromConsumer2) = (await t.value, await iterator.next())
    let collected = Set([collectedFromConsumer1, collectedFromConsumer2])

    XCTAssertEqual(collected, expected)
  }

  func test_asyncSubject_ends_alls_iterators_and_discards_additional_sent_values_when_finish_is_called() async {
    let subject = AsyncSubject<String>()
    let complete = ManagedCriticalState(false)
    let finished = expectation(description: "finished")

    Task {
      subject.finish()
      complete.withCriticalRegion { $0 = true }
      finished.fulfill()
    }

    let valueFromConsumer1 = ManagedCriticalState<String?>(nil)
    let valueFromConsumer2 = ManagedCriticalState<String?>(nil)

    let received = expectation(description: "received")
    received.expectedFulfillmentCount = 2

    let pastEnd = expectation(description: "pastEnd")
    pastEnd.expectedFulfillmentCount = 2

    Task {
      var iterator = subject.makeAsyncIterator()
      let ending = await iterator.next()
      valueFromConsumer1.withCriticalRegion { $0 = ending }
      received.fulfill()
      let item = await iterator.next()
      XCTAssertNil(item)
      pastEnd.fulfill()
    }

    Task {
      var iterator = subject.makeAsyncIterator()
      let ending = await iterator.next()
      valueFromConsumer2.withCriticalRegion { $0 = ending }
      received.fulfill()
      let item = await iterator.next()
      XCTAssertNil(item)
      pastEnd.fulfill()
    }
    
    wait(for: [finished, received], timeout: 1.0)

    XCTAssertTrue(complete.withCriticalRegion { $0 })
    XCTAssertEqual(valueFromConsumer1.withCriticalRegion { $0 }, nil)
    XCTAssertEqual(valueFromConsumer2.withCriticalRegion { $0 }, nil)

    wait(for: [pastEnd], timeout: 1.0)
    let additionalSend = expectation(description: "additional send")
    Task {
      subject.send("test")
      additionalSend.fulfill()
    }
    wait(for: [additionalSend], timeout: 1.0)
  }

  func test_asyncSubject_ends_iterator_when_task_is_cancelled() async {
    let subject = AsyncSubject<String>()
    let ready = expectation(description: "ready")
    let task: Task<String?, Never> = Task {
      var iterator = subject.makeAsyncIterator()
      ready.fulfill()
      return await iterator.next()
    }
    wait(for: [ready], timeout: 1.0)
    task.cancel()
    let value = await task.value
    XCTAssertNil(value)
  }

  func test_asyncThrowingSubject_delivers_values_when_two_producers_and_two_consumers() async throws {
    let (sentFromProducer1, sentFromProducer2) = ("test1", "test2")
    let expected = Set([sentFromProducer1, sentFromProducer2])

    let subject = AsyncThrowingSubject<String, Error>()
    Task {
      subject.send("test1")
    }
    Task {
      subject.send("test2")
    }
    
    let t: Task<String?, Error> = Task {
      var iterator = subject.makeAsyncIterator()
      let value = try await iterator.next()
      return value
    }
    var iterator = subject.makeAsyncIterator()

    let (collectedFromConsumer1, collectedFromConsumer2) = (try await t.value, try await iterator.next())
    let collected = Set([collectedFromConsumer1, collectedFromConsumer2])
    
    XCTAssertEqual(collected, expected)
  }
  
  func test_asyncThrowingSubject_throws_and_discards_additional_sent_values_when_fail_is_called() async {
    let sendImmediatelyResumes = expectation(description: "Send immediately resumes after fail")

    let subject = AsyncThrowingSubject<String, Error>()
    subject.fail(Failure())

    var iterator = subject.makeAsyncIterator()
    do {
      let _ = try await iterator.next()
      XCTFail("The AsyncThrowingSubject should have thrown")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }

    do {
      let pastFailure = try await iterator.next()
      XCTAssertNil(pastFailure)
    } catch {
      XCTFail("The AsyncThrowingSubject should not fail when failure has already been fired")
    }

    subject.send("send")
    sendImmediatelyResumes.fulfill()
    wait(for: [sendImmediatelyResumes], timeout: 1.0)
  }

  func test_asyncThrowingSubject_ends_alls_iterators_and_discards_additional_sent_values_when_finish_is_called() async {
    let subject = AsyncThrowingSubject<String, Error>()
    let complete = ManagedCriticalState(false)
    let finished = expectation(description: "finished")
    
    Task {
      subject.finish()
      complete.withCriticalRegion { $0 = true }
      finished.fulfill()
    }

    let valueFromConsumer1 = ManagedCriticalState<String?>(nil)
    let valueFromConsumer2 = ManagedCriticalState<String?>(nil)

    let received = expectation(description: "received")
    received.expectedFulfillmentCount = 2

    let pastEnd = expectation(description: "pastEnd")
    pastEnd.expectedFulfillmentCount = 2

    Task {
      var iterator = subject.makeAsyncIterator()
      let ending = try await iterator.next()
      valueFromConsumer1.withCriticalRegion { $0 = ending }
      received.fulfill()
      let item = try await iterator.next()
      XCTAssertNil(item)
      pastEnd.fulfill()
    }

    Task {
      var iterator = subject.makeAsyncIterator()
      let ending = try await iterator.next()
      valueFromConsumer2.withCriticalRegion { $0 = ending }
      received.fulfill()
      let item = try await iterator.next()
      XCTAssertNil(item)
      pastEnd.fulfill()
    }

    wait(for: [finished, received], timeout: 1.0)

    XCTAssertTrue(complete.withCriticalRegion { $0 })
    XCTAssertEqual(valueFromConsumer1.withCriticalRegion { $0 }, nil)
    XCTAssertEqual(valueFromConsumer2.withCriticalRegion { $0 }, nil)

    wait(for: [pastEnd], timeout: 1.0)
    let additionalSend = expectation(description: "additional send")
    Task {
      subject.send("test")
      additionalSend.fulfill()
    }
    wait(for: [additionalSend], timeout: 1.0)
  }

  func test_asyncThrowingSubject_ends_iterator_when_task_is_cancelled() async throws {
    let subject = AsyncThrowingSubject<String, Error>()
    let ready = expectation(description: "ready")
    let task: Task<String?, Error> = Task {
      var iterator = subject.makeAsyncIterator()
      ready.fulfill()
      return try await iterator.next()
    }
    wait(for: [ready], timeout: 1.0)
    task.cancel()
    let value = try await task.value
    XCTAssertNil(value)
  }
}

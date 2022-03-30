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
  func test_channel() async {
    let channel = AsyncChannel<String>()
    Task {
      await channel.send("test1")
    }
    Task {
      await channel.send("test2")
    }
    
    let t: Task<String?, Never> = Task {
      var iterator = channel.makeAsyncIterator()
      let value = await iterator.next()
      return value
    }
    var iterator = channel.makeAsyncIterator()
    let value = await iterator.next()
    let other = await t.value
    
    XCTAssertEqual(Set([value, other]), Set(["test1", "test2"]))
  }
  
  func test_throwing_channel() async throws {
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
    let value = try await iterator.next()
    let other = try await t.value
    
    XCTAssertEqual(Set([value, other]), Set(["test1", "test2"]))
  }
  
  func test_throwing() async {
    let channel = AsyncThrowingChannel<String, Error>()
    Task {
      await channel.fail(Failure())
    }
    var iterator = channel.makeAsyncIterator()
    do {
      let _ = try await iterator.next()
      XCTFail()
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }
  
  func test_send_finish() async {
    let channel = AsyncChannel<String>()
    let complete = ManagedCriticalState(false)
    let finished = expectation(description: "finished")
    Task {
      await channel.finish()
      complete.withCriticalRegion { $0 = true }
      finished.fulfill()
    }
    XCTAssertFalse(complete.withCriticalRegion { $0 })
    let value = ManagedCriticalState<String?>(nil)
    let received = expectation(description: "received")
    let pastEnd = expectation(description: "pastEnd")
    Task {
      var iterator = channel.makeAsyncIterator()
      let ending = await iterator.next()
      value.withCriticalRegion { $0 = ending }
      received.fulfill()
      let item = await iterator.next()
      XCTAssertNil(item)
      pastEnd.fulfill()
    }
    wait(for: [finished, received], timeout: 1.0)
    XCTAssertTrue(complete.withCriticalRegion { $0 })
    XCTAssertEqual(value.withCriticalRegion { $0 }, nil)
    wait(for: [pastEnd], timeout: 1.0)
    let additionalSend = expectation(description: "additional send")
    Task {
      await channel.send("test")
      additionalSend.fulfill()
    }
    wait(for: [additionalSend], timeout: 1.0)
  }
  
  func test_cancellation() async {
    let channel = AsyncChannel<String>()
    let ready = expectation(description: "ready")
    let task: Task<String?, Never> = Task {
      var iterator = channel.makeAsyncIterator()
      ready.fulfill()
      return await iterator.next()
    }
    wait(for: [ready], timeout: 1.0)
    task.cancel()
    let value = await task.value
    XCTAssertNil(value)
  }
  
  func test_sendCancellation() async {
    let channel = AsyncChannel<Int>()
    let notYetDone = expectation(description: "not yet done")
    notYetDone.isInverted = true
    let done = expectation(description: "done")
    let task = Task {
      await channel.send(1)
      notYetDone.fulfill()
      done.fulfill()
    }
    wait(for: [notYetDone], timeout: 0.1)
    task.cancel()
    wait(for: [done], timeout: 1.0)
  }
  
  func test_sendCancellation_throwing() async {
    let channel = AsyncThrowingChannel<Int, Error>()
    let notYetDone = expectation(description: "not yet done")
    notYetDone.isInverted = true
    let done = expectation(description: "done")
    let task = Task {
      await channel.send(1)
      notYetDone.fulfill()
      done.fulfill()
    }
    wait(for: [notYetDone], timeout: 0.1)
    task.cancel()
    wait(for: [done], timeout: 1.0)
  }
  
  func test_cancellation_throwing() async throws {
    let channel = AsyncThrowingChannel<String, Error>()
    let ready = expectation(description: "ready")
    let task: Task<String?, Error> = Task {
      var iterator = channel.makeAsyncIterator()
      ready.fulfill()
      return try await iterator.next()
    }
    wait(for: [ready], timeout: 1.0)
    task.cancel()
    let value = try await task.value
    XCTAssertNil(value)
  }
}

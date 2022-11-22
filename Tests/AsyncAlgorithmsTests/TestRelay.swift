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

final class TestRelay: XCTestCase {
  
  // MARK: - AsyncRelay
  
  func test_relay_basic() async {
    let source = [0, 1, 2, 3, 4]
    let expected = source
    let relay = AsyncRelay { yield in
      for item in source { await yield(item) }
    }
    var collected = [Int]()
    while let item = await relay.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)
  }
  
  func test_relay_returns_nil_past_end() async {
    let source = [0, 1, 2, 3, 4]
    let relay = AsyncRelay { yield in
      for item in source { await yield(item) }
    }
    while let item = await relay.next() { XCTAssertNotNil(item) }
    let pastEnd = await relay.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_relay_consumer_cancellation() async {
    let cancelled = expectation(description: "consumer cancelled")
    let started = expectation(description: "relay started")
    started.assertForOverFulfill = false
    let relay = AsyncRelay<Int> { yield in
      while !Task.isCancelled {
        started.fulfill()
      }
    }
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        let item = await relay.next()
        XCTAssertNil(item)
        cancelled.fulfill()
      }
      wait(for: [started], timeout: 1.0)
      group.cancelAll()
    }
    wait(for: [cancelled], timeout: 1.0)
  }
  
  func test_relay_inner_task_cancellation() async {
    let started = expectation(description: "started indefinite task")
    let finished = expectation(description: "finished indefinite task")
    started.assertForOverFulfill = false
    var relay: AsyncRelay<Int>! = AsyncRelay { yield in
      while !Task.isCancelled {
        started.fulfill()
        await yield(0)
      }
      finished.fulfill()
    }
    let _ = await relay.next() // kicks off task
    relay = nil
    wait(for: [started, finished], timeout: 1.0)
  }
  
  func test_relay_basic_parallelized() async {
    let source = Array(0..<100)
    let expected = source.reduce(0, +)
    let relay = AsyncRelay { yield in
      for item in source { await yield(item) }
    }
    let result = await withTaskGroup(of: [Int].self) { group in
      for _ in 0..<16 {
        group.addTask {
          var collected = [Int]()
          while let item = await relay.next() { collected.append(item) }
          return collected
        }
      }
      let results = await Array(group)
      return results.flatMap { $0 }.reduce(0, +)
    }
    XCTAssertEqual(expected, result)
  }
  
  func test_relay_consumer_cancellation_parallelized() async {
    var tasks = [Task<Void, Never>]()
    var iterated = [XCTestExpectation]()
    var finished = [XCTestExpectation]()
    let relay = AsyncRelay { yield in
      while Task.isCancelled == false {
        await yield(1)
      }
    }
    for _ in 0..<64 {
      let iterate = expectation(description: "task iterated")
      iterate.assertForOverFulfill = false
      let finish = expectation(description: "task finished")
      iterated.append(iterate)
      finished.append(finish)
      let task = Task {
        while let _ = await relay.next() {
          iterate.fulfill()
          await Task.yield()
        }
        finish.fulfill()
      }
      tasks.append(task)
    }
    wait(for: iterated, timeout: 1.0)
    for task in tasks { task.cancel() }
    wait(for: finished, timeout: 1.0)
  }
  
  // MARK: - AsyncThrowingRelay
  
  func test_throwing_relay_basic() async throws {
    let source = [0, 1, 2, 3, 4]
    let expected = source
    let relay = AsyncThrowingRelay { yield in
      for item in source { await yield(item) }
    }
    var collected = [Int]()
    while let item = try await relay.next() {
      collected.append(item)
    }
    XCTAssertEqual(expected, collected)
  }
  
  func test_throwing_relay_returns_nil_past_end() async throws {
    let source = [0, 1, 2, 3, 4]
    let relay = AsyncThrowingRelay { yield in
      for item in source { await yield(item) }
    }
    while let item = try await relay.next() { XCTAssertNotNil(item) }
    let pastEnd = try await relay.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_relay_throws() async {
    let source = [0, 1, 2, 3, 4]
    let expected = [0, 1, 2]
    let relay = AsyncThrowingRelay { yield in
      for item in source { await yield(try throwOn(3, item)) }
    }
    var collected = [Int]()
    var failure: Error?
    do {
      while let item = try await relay.next() {
        collected.append(item)
      }
    }
    catch {
      failure = error
    }
    XCTAssertEqual(expected, collected)
    XCTAssertEqual(Failure(), failure as? Failure)
  }
  
  func test_throwing_relay_returns_nil_past_end_after_throw() async throws {
    let source = [0, 1, 2, 3, 4]
    let relay = AsyncThrowingRelay { yield in
      for item in source { await yield(try throwOn(3, item)) }
    }
    var failure: Error?
    do {
      while let item = try await relay.next() { XCTAssertNotNil(item) }
    }
    catch {
      failure = error
    }
    let pastEnd = try await relay.next()
    XCTAssertNil(pastEnd)
    XCTAssertEqual(Failure(), failure as? Failure)
  }
  
  func test_throwing_relay_consumer_cancellation() async {
    let cancelled = expectation(description: "consumer cancelled")
    let started = expectation(description: "relay started")
    started.assertForOverFulfill = false
    let relay = AsyncThrowingRelay<Int> { yield in
      while true {
        started.fulfill()
        if Task.isCancelled { break }
      }
    }
    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        do {
          let item = try await relay.next()
          XCTAssertNil(item)
          cancelled.fulfill()
        }
        catch { XCTFail("threw unexpectedly") }
      }
      wait(for: [started], timeout: 1.0)
      group.cancelAll()
    }
    wait(for: [cancelled], timeout: 1.0)
  }
  
  func test_throwing_relay_inner_task_cancellation() async {
    let started = expectation(description: "started indefinite task")
    let finished = expectation(description: "finished indefinite task")
    started.assertForOverFulfill = false
    var relay: AsyncThrowingRelay<Int>! = AsyncThrowingRelay { yield in
      await yield(0)
      while true {
        started.fulfill()
        if Task.isCancelled { break }
      }
      finished.fulfill()
    }
    let _ = try? await relay.next() // kicks off task
    relay = nil
    wait(for: [started, finished], timeout: 1.0)
  }
  
  func test_throwing_relay_basic_parallelized() async throws {
    let source = Array(0..<100)
    let expected = source.reduce(0, +)
    let relay = AsyncThrowingRelay { yield in
      for item in source { await yield(item) }
    }
    let result = try await withThrowingTaskGroup(of: [Int].self) { group in
      for _ in 0..<16 {
        group.addTask {
          var collected = [Int]()
          while let item = try await relay.next() {
            collected.append(item)
            await Task.yield()
          }
          return collected
        }
      }
      let results = try await Array(group)
      return results.flatMap { $0 }.reduce(0, +)
    }
    XCTAssertEqual(expected, result)
  }
  
  func test_throwing_relay_parallelized_throws() async {
    let source = Array(0..<100)
    let expected = 50
    let threw = expectation(description: "throws")
    let relay = AsyncThrowingRelay { yield in
      for item in source {
        let _ = try throwOn(50, item)
        await yield(1)
      }
    }
    let result = await withTaskGroup(of: [Int].self) { group in
      for _ in 0..<16 {
        group.addTask {
          var collected = [Int]()
          do {
            while let item = try await relay.next() {
              collected.append(item)
              await Task.yield()
            }
          }
          catch {
            threw.fulfill()
          }
          return collected
        }
      }
      let results = await Array(group)
      return results.flatMap { $0 }.reduce(0, +)
    }
    wait(for: [threw], timeout: 1.0)
    XCTAssertEqual(expected, result)
  }
  
  func test_throwing_relay_consumer_cancellation_parallelized() async {
    var tasks = [Task<Void, Never>]()
    var iterated = [XCTestExpectation]()
    var finished = [XCTestExpectation]()
    let relay = AsyncThrowingRelay { yield in
      while Task.isCancelled == false {
        await yield(1)
      }
    }
    for _ in 0..<64 {
      let iterate = expectation(description: "task iterated")
      iterate.assertForOverFulfill = false
      let finish = expectation(description: "task finished")
      iterated.append(iterate)
      finished.append(finish)
      let task = Task {
        do {
          while let _ = try await relay.next() {
            iterate.fulfill()
            await Task.yield()
          }
        }
        catch { XCTFail("threw unexpectedly") }
        finish.fulfill()
      }
      tasks.append(task)
    }
    wait(for: iterated, timeout: 1.0)
    for task in tasks { task.cancel() }
    wait(for: finished, timeout: 1.0)
  }
  
  // MARK: - AsyncRelaySequence
  
  func test_relay_sequence_basic() async {
    let source = [0, 1, 2, 3, 4]
    let expected = source
    let sequence = AsyncRelaySequence { yield in
      for item in source { await yield(item) }
    }
    var collected0 = [Int]()
    var collected1 = [Int]()
    var collected2 = [Int]()
    for await item in sequence { collected0.append(item) }
    for await item in sequence { collected1.append(item) }
    for await item in sequence { collected2.append(item) }
    XCTAssertEqual(expected, collected0)
    XCTAssertEqual(expected, collected1)
    XCTAssertEqual(expected, collected2)
  }
  
  // MARK: - AsyncRelayThrowingSequence
  
  func test_relay_throwing_sequence_basic() async throws {
    let source = [0, 1, 2, 3, 4]
    let expected = source
    let sequence = AsyncThrowingRelaySequence { yield in
      for item in source { await yield(item) }
    }
    var collected0 = [Int]()
    var collected1 = [Int]()
    var collected2 = [Int]()
    for try await item in sequence { collected0.append(item) }
    for try await item in sequence { collected1.append(item) }
    for try await item in sequence { collected2.append(item) }
    XCTAssertEqual(expected, collected0)
    XCTAssertEqual(expected, collected1)
    XCTAssertEqual(expected, collected2)
  }
}

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

final class TestBroadcast: XCTestCase {
  func test_given_a_base_sequence_when_broadcasting_to_two_tasks_then_the_base_sequence_is_iterated_once() async {
    // Given
    let elements = (0..<10).map { $0 }
    let base = ReportingAsyncSequence(elements)

    let expectedNexts = elements.map { _ in ReportingAsyncSequence<Int>.Event.next }

    // When
    let broadcasted = base.broadcast()
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for await _ in broadcasted {}
      }
      group.addTask {
        for await _ in broadcasted {}
      }
      await group.waitForAll()
    }

    // Then
    XCTAssertEqual(
      base.events,
      [ReportingAsyncSequence<Int>.Event.makeAsyncIterator] + expectedNexts + [ReportingAsyncSequence<Int>.Event.next]
    )
  }

  func test_given_a_base_sequence_when_broadcasting_to_two_tasks_then_they_receive_the_base_elements() async {
    // Given
    let base = (0..<10).map { $0 }
    let expected = (0...4).map { $0 }

    // When
    let broadcasted = base.async.map { try throwOn(5, $0) }.broadcast()
    let results = await withTaskGroup(of: [Int].self) { group in
      group.addTask {
        var received = [Int]()
        do {
          for try await element in broadcasted {
            received.append(element)
          }
          XCTFail("The broadcast should fail before finish")
        } catch {
          XCTAssertTrue(error is Failure)
        }

        return received
      }
      group.addTask {
        var received = [Int]()
        do {
          for try await element in broadcasted {
            received.append(element)
          }
          XCTFail("The broadcast should fail before finish")
        } catch {
          XCTAssertTrue(error is Failure)
        }

        return received
      }

      return await Array(group)
    }

    // Then
    XCTAssertEqual(results[0], expected)
    XCTAssertEqual(results[0], results[1])
  }

  func test_given_a_throwing_base_sequence_when_broadcasting_to_two_tasks_then_they_receive_the_base_elements_and_failure() async {
    // Given
    let base = (0..<10).map { $0 }

    // When
    let broadcasted = base.async.broadcast()
    let results = await withTaskGroup(of: [Int].self) { group in
      group.addTask {
        await Array(broadcasted)
      }
      group.addTask {
        await Array(broadcasted)
      }
      return await Array(group)
    }

    // Then
    XCTAssertEqual(results[0], base)
    XCTAssertEqual(results[0], results[1])
  }

  func test_given_a_base_sequence_when_broadcasting_to_two_tasks_then_they_receive_finish_and_pastEnd_is_nil() async {
    // Given
    let base = (0..<10).map { $0 }

    // When
    let broadcasted = base.async.broadcast()
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        var iterator = broadcasted.makeAsyncIterator()
        while let _ = await iterator.next() {}
        let pastEnd = await iterator.next()

        // Then
        XCTAssertNil(pastEnd)
      }
      group.addTask {
        var iterator = broadcasted.makeAsyncIterator()
        while let _ = await iterator.next() {}
        let pastEnd = await iterator.next()

        // Then
        XCTAssertNil(pastEnd)
      }

      await group.waitForAll()
    }
  }

  func test_given_a_base_sequence_when_broadcasting_to_two_tasks_then_the_buffer_is_used() async {
    let task1IsIsFinished = expectation(description: "")

    // Given
    let base = (0..<10).map { $0 }

    // When
    let broadcasted = base.async.broadcast()
    let results = await withTaskGroup(of: [Int].self) { group in
      group.addTask {
        let result = await Array(broadcasted)
        task1IsIsFinished.fulfill()
        return result
      }
      group.addTask {
        var result = [Int]()
        var iterator = broadcasted.makeAsyncIterator()
        let firstElement = await iterator.next()
        result.append(firstElement!)
        self.wait(for: [task1IsIsFinished], timeout: 1.0)

        while let element = await iterator.next() {
          result.append(element)
        }

        return result
      }
      return await Array(group)
    }

    // Then
    XCTAssertEqual(results[0], base)
    XCTAssertEqual(results[0], results[1])
  }

  func test_given_a_channel_when_broadcasting_to_two_tasks_then_they_received_the_channel_elements() async {
    // Given
    let elements = (0..<10).map { $0 }
    let base = AsyncChannel<Int>()

    // When
    let broadcasted = base.broadcast()
    let results = await withTaskGroup(of: [Int].self) { group in
      group.addTask {
        var sent = [Int]()
        for element in elements {
          sent.append(element)
          await base.send(element)
        }
        base.finish()
        return sent
      }
      group.addTask {
        await Array(broadcasted)
      }
      group.addTask {
        await Array(broadcasted)
      }
      return await Array(group)
    }

    // Then
    XCTAssertEqual(results[0], elements)
    XCTAssertEqual(results[0], results[1])
  }

  func test_given_a_broadcasted_sequence_when_cancelling_task_iteration_finishes() async {
    let task1CanCancel = expectation(description: "")
    let task1IsCancelled = expectation(description: "")

    let task2CanCancel = expectation(description: "")
    let task2IsCancelled = expectation(description: "")

    // Given
    let base = (0..<10).map { $0 }
    let broadcasted = base.async.broadcast()

    let task1 = Task {
      var received = [Int?]()

      var iterator = broadcasted.makeAsyncIterator()
      let element = await iterator.next()
      received.append(element)

      task1CanCancel.fulfill()

      wait(for: [task1IsCancelled], timeout: 1.0)

      // Then
      let pastCancelled = await iterator.next()
      XCTAssertNil(pastCancelled)

      return received
    }

    let task2 = Task {
      var received = [Int?]()

      var iterator = broadcasted.makeAsyncIterator()
      let element = await iterator.next()
      received.append(element)

      task2CanCancel.fulfill()

      wait(for: [task2IsCancelled], timeout: 1.0)

      // Then
      let pastCancelled = await iterator.next()
      XCTAssertNil(pastCancelled)

      return received
    }

    wait(for: [task1CanCancel, task2CanCancel], timeout: 1.0)

    // When
    task1.cancel()
    task2.cancel()

    task1IsCancelled.fulfill()
    task2IsCancelled.fulfill()

    let elements1 = await task1.value
    let elements2 = await task2.value

    // Then
    XCTAssertEqual(elements1, elements2)
  }
}

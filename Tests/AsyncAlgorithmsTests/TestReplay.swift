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

final class TestReplay: XCTestCase {
  func test_given_a_replayed_sequence_when_next_sequence_is_iterated_then_elements_are_replayed_in_the_limit_of_count() async {
    let channel = AsyncChannel<Int>()

    // Given
    let replayed = channel.replay(count: 2)

    Task {
      await channel.send(1)
      await channel.send(2)
      await channel.send(3)
    }

    var iterator1 = replayed.makeAsyncIterator()
    _ = await iterator1.next() // 1
    _ = await iterator1.next() // 2
    _ = await iterator1.next() // 3

    Task {
      await channel.send(4)
      await channel.send(5)
      await channel.send(6)
    }

    // When
    var received = [Int]()
    var iterator2 = replayed.makeAsyncIterator()
    received.append(await iterator2.next()!) // 2
    received.append(await iterator2.next()!) // 3
    received.append(await iterator2.next()!) // 4
    received.append(await iterator2.next()!) // 5
    received.append(await iterator2.next()!) // 6

    // Then
    XCTAssertEqual(received, [2, 3, 4, 5, 6])
  }

  func test_given_a_replayed_sequence_when_base_is_finished_then_pastEnd_is_nil() async {
    // Given
    let replayed = [1, 2, 3].async.replay(count: 0)

    var iterator = replayed.makeAsyncIterator()

    // When
    while let _ = await iterator.next() {}

    // Then
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_given_a_failed_replayed_sequence_when_next_sequence_is_iterated_then_elements_are_replayed_with_failure() async throws {
    let channel = AsyncThrowingChannel<Int, Error>()

    // Given
    let replayed = channel.replay(count: 2)

    Task {
      await channel.send(1)
      await channel.send(2)
      channel.fail(Failure())
    }

    var iterator1 = replayed.makeAsyncIterator()
    _ = try await iterator1.next() // 1
    _ = try await iterator1.next() // 2
    _ = try? await iterator1.next() // failure

    // When
    var received = [Int]()
    do {
      for try await element in replayed {
        received.append(element)
      }
      XCTFail("Replayed should fail at element number 2")
    } catch {
      XCTAssertTrue(error is Failure)
    }

    // Then
    XCTAssertEqual(received, [2])
  }
}

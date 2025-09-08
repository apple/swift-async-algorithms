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

final class TestBuffer: XCTestCase {
  func test_given_a_base_sequence_when_buffering_with_unbounded_then_the_buffer_is_filled_in() async {
    // Given
    var base = GatedSequence([1, 2, 3, 4, 5])
    let buffered = base.buffer(policy: .unbounded)
    var iterator = buffered.makeAsyncIterator()

    // When
    base.advance()

    // Then
    var value = await iterator.next()
    XCTAssertEqual(value, 1)

    // When
    base.advance()
    base.advance()
    base.advance()

    // Then
    value = await iterator.next()
    XCTAssertEqual(value, 2)

    value = await iterator.next()
    XCTAssertEqual(value, 3)

    value = await iterator.next()
    XCTAssertEqual(value, 4)

    // When
    base.advance()
    base.advance()

    // Then
    value = await iterator.next()
    XCTAssertEqual(value, 5)
    value = await iterator.next()
    XCTAssertEqual(value, nil)

    let pastEnd = await iterator.next()
    XCTAssertEqual(value, pastEnd)
  }

  func test_given_a_failable_base_sequence_when_buffering_with_unbounded_then_the_failure_is_forwarded() async {
    // Given
    var gated = GatedSequence([1, 2, 3, 4, 5, 6, 7])
    let base = gated.map { try throwOn(3, $0) }
    let buffered = base.buffer(policy: .unbounded)
    var iterator = buffered.makeAsyncIterator()

    // When
    gated.advance()

    // Then
    var value = try! await iterator.next()
    XCTAssertEqual(value, 1)

    // When
    gated.advance()
    gated.advance()
    gated.advance()

    // Then
    value = try! await iterator.next()
    XCTAssertEqual(value, 2)

    // When
    gated.advance()
    gated.advance()
    gated.advance()
    gated.advance()

    // Then
    do {
      value = try await iterator.next()
      XCTFail("next() should have thrown.")
    } catch {
      XCTAssert(error is Failure)
    }

    var pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)
  }

  #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)
  func test_given_a_base_sequence_when_bufferingOldest_then_the_policy_is_applied() async {
    validate {
      "X-12-   34-    5   |"
      $0.inputs[0].buffer(policy: .bufferingOldest(2))
      "X,,,[1,],,[2,],[3,][5,]|"
    }
  }

  func test_given_a_base_sequence_when_bufferingOldest_with_0_limit_then_the_policy_is_transparent() async {
    validate {
      "X-12-   34-    5   |"
      $0.inputs[0].buffer(policy: .bufferingOldest(0))
      "X-12-   34-    5   |"
    }
  }

  func test_given_a_base_sequence_when_bufferingOldest_at_slow_pace_then_no_element_is_dropped() async {
    validate {
      "X-12   3   4   5   |"
      $0.inputs[0].buffer(policy: .bufferingOldest(2))
      "X,,[1,][2,][3,][45]|"
    }
  }

  func test_given_a_failable_base_sequence_when_bufferingOldest_then_the_failure_is_forwarded() async {
    validate {
      "X-12345^"
      $0.inputs[0].buffer(policy: .bufferingOldest(2))
      "X,,,,,,[12^]"
    }
  }

  func test_given_a_base_sequence_when_bufferingNewest_then_the_policy_is_applied() async {
    validate {
      "X-12-   34    -5|"
      $0.inputs[0].buffer(policy: .bufferingLatest(2))
      "X,,,[1,],,[3,],[4,][5,]|"
    }
  }

  func test_given_a_base_sequence_when_bufferingNewest_with_limit_0_then_the_policy_is_transparent() async {
    validate {
      "X-12-   34    -5|"
      $0.inputs[0].buffer(policy: .bufferingLatest(0))
      "X-12-   34    -5|"
    }
  }

  func test_given_a_base_sequence_when_bufferingNewest_at_slow_pace_then_no_element_is_dropped() async {
    validate {
      "X-12   3   4   5   |"
      $0.inputs[0].buffer(policy: .bufferingLatest(2))
      "X,,[1,][2,][3,][45]|"
    }
  }

  func test_given_a_failable_base_sequence_when_bufferingNewest_then_the_failure_is_forwarded() async {
    validate {
      "X-12345^"
      $0.inputs[0].buffer(policy: .bufferingLatest(2))
      "X,,,,,,[45^]"
    }
  }
  #endif

  func
    test_given_a_buffered_with_unbounded_sequence_when_cancelling_consumer_then_the_iteration_finishes_and_the_base_is_cancelled()
    async
  {
    // Given
    let buffered = Indefinite(value: 1).async.buffer(policy: .unbounded)

    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let task = Task {
      var firstIteration = false
      for await _ in buffered {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }
    // ensure the task actually starts
    await fulfillment(of: [iterated], timeout: 1.0)

    // When
    task.cancel()

    // Then
    await fulfillment(of: [finished], timeout: 1.0)
  }

  func test_given_a_base_sequence_when_buffering_with_bounded_then_the_buffer_is_filled_in_and_suspends() async {
    // Gicen
    var base = GatedSequence([1, 2, 3, 4, 5])
    let buffered = base.buffer(policy: .bounded(2))
    var iterator = buffered.makeAsyncIterator()

    // When
    base.advance()

    // Then
    var value = await iterator.next()
    XCTAssertEqual(value, 1)

    // When
    base.advance()
    base.advance()
    base.advance()

    // Then
    value = await iterator.next()
    XCTAssertEqual(value, 2)
    value = await iterator.next()
    XCTAssertEqual(value, 3)
    value = await iterator.next()
    XCTAssertEqual(value, 4)

    // When
    base.advance()
    base.advance()

    // Then
    value = await iterator.next()
    XCTAssertEqual(value, 5)
    value = await iterator.next()
    XCTAssertEqual(value, nil)

    let pastEnd = await iterator.next()
    XCTAssertEqual(value, pastEnd)
  }

  func test_given_a_failable_base_sequence_when_buffering_with_bounded_then_the_failure_is_forwarded() async {
    // Given
    var gated = GatedSequence([1, 2, 3, 4, 5, 6, 7])
    let base = gated.map { try throwOn(3, $0) }
    let buffered = base.buffer(policy: .bounded(5))
    var iterator = buffered.makeAsyncIterator()

    // When
    gated.advance()

    // Then
    var value = try! await iterator.next()
    XCTAssertEqual(value, 1)

    // When
    gated.advance()
    gated.advance()
    gated.advance()

    // Then
    value = try! await iterator.next()
    XCTAssertEqual(value, 2)

    // When
    gated.advance()
    gated.advance()
    gated.advance()
    gated.advance()

    // Then
    do {
      value = try await iterator.next()
      XCTFail("next() should have thrown.")
    } catch {
      XCTAssert(error is Failure)
    }

    var pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)

    pastFailure = try! await iterator.next()
    XCTAssertNil(pastFailure)
  }

  func
    test_given_a_buffered_bounded_sequence_when_cancelling_consumer_then_the_iteration_finishes_and_the_base_is_cancelled()
    async
  {
    // Given
    let buffered = Indefinite(value: 1).async.buffer(policy: .bounded(3))

    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let task = Task {
      var firstIteration = false
      for await _ in buffered {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }
    // ensure the other task actually starts
    await fulfillment(of: [iterated], timeout: 1.0)

    // When
    task.cancel()

    // Then
    await fulfillment(of: [finished], timeout: 1.0)
  }

  #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)
  func test_given_a_base_sequence_when_bounded_with_limit_0_then_the_policy_is_transparent() async {
    validate {
      "X-12-   34    -5|"
      $0.inputs[0].buffer(policy: .bounded(0))
      "X-12-   34    -5|"
    }
  }
  #endif
}

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

private struct DebounceTestError: Error, Equatable, Sendable {
  let value: Int
}

final class TestDebounce: XCTestCase {
  #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)
  func test_delayingValues() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcd----e---f-g----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "------d----e-----g-|"
    }
  }

  func test_delayingValues_dangling_last() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcd----e---f-g-|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "------d----e----[g|]"
    }
  }

  func test_finishDoesntDebounce() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "a|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-[a|]"
    }
  }

  func test_throwDoesntDebounce() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "a^"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-^"
    }
  }

  func test_upstreamFailureWithoutOutstandingDemand() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "a^"
      $0.inputs[0].debounce(for: .steps(0), clock: $0.clock)
      "a,,,^"
    }
  }

  func test_upstreamFailureWithoutElementsPreservesError() async throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }

    let expectedError = DebounceTestError(value: 1)
    let (stream, source) = AsyncThrowingStream<Int, Error>.makeStream()
    source.finish(throwing: expectedError)

    var iterator = stream.debounce(for: .milliseconds(10), clock: .continuous).makeAsyncIterator()
    do {
      _ = try await iterator.next()
      XCTFail("Expected the upstream error")
    } catch let error as DebounceTestError {
      XCTAssertEqual(error, expectedError)
    }

    let result = try await iterator.next()
    XCTAssertNil(result)
  }

  func test_upstreamFailureAfterElementAndWithoutDemandPreservesError() async throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }

    let expectedError = DebounceTestError(value: 2)
    let (stream, source) = AsyncThrowingStream<Int, Error>.makeStream()
    source.yield(1)
    let finisher = Task {
      try? await Task.sleep(for: .milliseconds(100))
      source.finish(throwing: expectedError)
    }
    defer { finisher.cancel() }

    var iterator = stream.debounce(for: .milliseconds(10), clock: .continuous).makeAsyncIterator()
    let first = try await iterator.next()
    XCTAssertEqual(first, 1)

    // The upstream fails while the consumer has no outstanding demand.
    try await Task.sleep(for: .milliseconds(300))

    do {
      _ = try await iterator.next()
      XCTFail("Expected the upstream error")
    } catch let error as DebounceTestError {
      XCTAssertEqual(error, expectedError)
    }

    // Consuming the failure completes the iterator; it must not produce another value
    // or resume completion more than once.
    let result = try await iterator.next()
    XCTAssertNil(result)
  }

  func test_noValues() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "----|"
    }
  }
  #endif

  func test_Rethrows() async throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }

    let debounce = [1].async.debounce(for: .zero, clock: ContinuousClock())
    for await _ in debounce {}

    let throwingDebounce = [1].async.map { try throwOn(2, $0) }.debounce(for: .zero, clock: ContinuousClock())
    for try await _ in throwingDebounce {}
  }

  func test_debounce_when_cancelled() async throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }

    let t = Task {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      let c1 = Indefinite(value: "test1").async
      for await _ in c1.debounce(for: .seconds(1), clock: .continuous) {}
    }
    t.cancel()
  }
}

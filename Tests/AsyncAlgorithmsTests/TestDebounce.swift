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

final class TestDebounce: XCTestCase {
  func test_delayingValues() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else { throw XCTSkip("Skipped due to Clock/Instant/Duration availability") }
    validate {
      "abcd----e---f-g----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "------d----e-----g-|"
    }
  }

  func test_delayingValues_dangling_last() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else { throw XCTSkip("Skipped due to Clock/Instant/Duration availability") }
    validate {
      "abcd----e---f-g-|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "------d----e----[g|]"
    }
  }

  
  func test_finishDoesntDebounce() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else { throw XCTSkip("Skipped due to Clock/Instant/Duration availability") }
    validate {
      "a|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-[a|]"
    }
  }
  
  func test_throwDoesntDebounce() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else { throw XCTSkip("Skipped due to Clock/Instant/Duration availability") }
    validate {
      "a^"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-^"
    }
  }
  
  func test_noValues() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else { throw XCTSkip("Skipped due to Clock/Instant/Duration availability") }
    validate {
      "----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "----|"
    }
  }

    func test_Rethrows() async throws {
        guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else { throw XCTSkip("Skipped due to Clock/Instant/Duration availability") }

        let debounce = [1].async.debounce(for: .zero, clock: ContinuousClock())
        for await _ in debounce {}

        let throwingDebounce = [1].async.map { try throwOn(2, $0) }.debounce(for: .zero, clock: ContinuousClock())
        for try await _ in throwingDebounce {}
    }
}

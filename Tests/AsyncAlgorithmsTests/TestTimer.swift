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
import AsyncSequenceValidation

final class TestTimer: XCTestCase {
  func test_tick1() {
    validate {
      AsyncTimerSequence(interval: .steps(1), clock: $0.clock).map { _ in "x" }
      "xxxxxxx[;|]"
    }
  }
  
  func test_tick2() {
    validate {
      AsyncTimerSequence(interval: .steps(2), clock: $0.clock).map { _ in "x" }
      "-x-x-x-[;|]"
    }
  }
  
  func test_tick3() {
    validate {
      AsyncTimerSequence(interval: .steps(3), clock: $0.clock).map { _ in "x" }
      "--x--x-[;|]"
    }
  }
  
  func test_tick2_event_skew3() {
    validate { diagram in
      AsyncTimerSequence(interval: .steps(2), clock: diagram.clock).map { [diagram] (_) -> String in
        try? await diagram.clock.sleep(until: diagram.clock.now.advanced(by: .steps(3)))
        return "x"
      }
      "----x--x-[;x|]"
    }
  }
}

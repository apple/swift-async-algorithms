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
  func test_delayingValues() {
    validate {
      "abcd----e---f-g----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "------d----e-----g-|"
    }
  }

  func test_delayingValues_dangling_last() {
    validate {
      "abcd----e---f-g-|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "------d----e----|"
    }
  }

  
  func test_finishDoesntDebounce() {
    validate {
      "a|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-|"
    }
  }
  
  func test_throwDoesntDebounce() {
    validate {
      "a^"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-^"
    }
  }
  
  func test_noValues() {
    validate {
      "----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "----|"
    }
  }
}

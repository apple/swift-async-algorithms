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
import MarbleDiagram

final class TestDebounce: XCTestCase {
  func test_delayingValues() {
    marbleDiagram {
      "abcd----e---f-g----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "------d----e-----g-|"
    }
  }
  
  func test_finishDoesntDebounce() {
    marbleDiagram {
      "a|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-|"
    }
  }
  
  func test_throwDoesntDebounce() {
    marbleDiagram {
      "a^"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "-^"
    }
  }
  
  func test_noValues() {
    marbleDiagram {
      "----|"
      $0.inputs[0].debounce(for: .steps(3), clock: $0.clock)
      "----|"
    }
  }
}

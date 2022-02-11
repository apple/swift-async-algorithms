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

final class TestThrottle: XCTestCase {
  func test_rate_0() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(0), clock: $0.clock)
      "abcdefghijk|"
    }
  }
  
  func test_rate_0_leading_edge() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(0), clock: $0.clock, latest: false)
      "abcdefghijk|"
    }
  }
  
  func test_rate_1() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(1), clock: $0.clock)
      "abcdefghijk|"
    }
  }
  
  func test_rate_1_leading_edge() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(1), clock: $0.clock, latest: false)
      "abcdefghijk|"
    }
  }
  
  func test_rate_2() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock)
      "-b-d-f-h-j-|"
    }
  }
  
  func test_rate_2_leading_edge() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock, latest: false)
      "-a-c-e-g-i-|"
    }
  }
  
  func test_rate_3() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(3), clock: $0.clock)
      "--c--f--i--|"
    }
  }
  
  func test_rate_3_leading_edge() {
    marbleDiagram {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(3), clock: $0.clock, latest: false)
      "--a--d--g--|"
    }
  }
  
  func test_throwing() {
    marbleDiagram {
      "abcdef^hijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock)
      "-b-d-f^"
    }
  }
  
  func test_throwing_leading_edge() {
    marbleDiagram {
      "abcdef^hijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock, latest: false)
      "-a-c-e^"
    }
  }
}

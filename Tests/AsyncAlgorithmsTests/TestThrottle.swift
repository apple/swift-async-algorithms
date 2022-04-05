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
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(0), clock: $0.clock)
      "abcdefghijk|"
    }
  }
  
  func test_rate_0_leading_edge() {
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(0), clock: $0.clock, latest: false)
      "abcdefghijk|"
    }
  }
  
  func test_rate_1() {
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(1), clock: $0.clock)
      "abcdefghijk|"
    }
  }
  
  func test_rate_1_leading_edge() {
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(1), clock: $0.clock, latest: false)
      "abcdefghijk|"
    }
  }
  
  func test_rate_2() {
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock)
      "a-c-e-g-i-k|"
    }
  }
  
  func test_rate_2_leading_edge() {
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock, latest: false)
      "a-b-d-f-h-j|"
    }
  }
  
  func test_rate_3() {
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(3), clock: $0.clock)
      "a--d--g--j-|"
    }
  }
  
  func test_rate_3_leading_edge() {
    validate {
      "abcdefghijk|"
      $0.inputs[0].throttle(for: .steps(3), clock: $0.clock, latest: false)
      "a--b--e--h-|"
    }
  }
  
  func test_throwing() {
    validate {
      "abcdef^hijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock)
      "a-c-e-^"
    }
  }
  
  func test_throwing_leading_edge() {
    validate {
      "abcdef^hijk|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock, latest: false)
      "a-b-d-^"
    }
  }
  
  func test_emission_2_rate_1() {
    validate {
      "-a-b-c-d-e-f-g-h-i-j-k-|"
      $0.inputs[0].throttle(for: .steps(1), clock: $0.clock)
      "-a-b-c-d-e-f-g-h-i-j-k-|"
    }
  }
  
  func test_emission_2_rate_2() {
    validate {
      "-a-b-c-d-e-f-g-h-i-j-k-|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock)
      "-a-b-c-d-e-f-g-h-i-j-k-|"
    }
  }
  
  func test_emission_3_rate_2() {
    validate {
      "--a--b--c--d--e--f--g|"
      $0.inputs[0].throttle(for: .steps(2), clock: $0.clock)
      "--a--b--c--d--e--f--g|"
    }
  }
  
  func test_emission_2_rate_3() {
    validate {
      "-a-b-c-d-e-f-g-h-i-j-k-|"
      $0.inputs[0].throttle(for: .steps(3), clock: $0.clock)
      "-a---c---e---g---i---k-|"
    }
  }
}

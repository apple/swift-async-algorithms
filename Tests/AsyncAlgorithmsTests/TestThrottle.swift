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
  #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)
  func test_rate_0() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(0), clock: $0.clock)
      "abcdefghijk|"
    }
  }

  func test_rate_0_leading_edge() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(0), clock: $0.clock, latest: false)
      "abcdefghijk|"
    }
  }

  func test_rate_1() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(1), clock: $0.clock)
      "abcdefghijk|"
    }
  }

  func test_rate_1_leading_edge() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(1), clock: $0.clock, latest: false)
      "abcdefghijk|"
    }
  }

  func test_rate_2() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(2), clock: $0.clock)
      "a-c-e-g-i-k|"
    }
  }

  func test_rate_2_leading_edge() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(2), clock: $0.clock, latest: false)
      "a-b-d-f-h-j|"
    }
  }

  func test_rate_3() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(3), clock: $0.clock)
      "a--d--g--j--[k|]"
    }
  }

  func test_rate_3_leading_edge() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijk|"
      $0.inputs[0]._throttle(for: .steps(3), clock: $0.clock, latest: false)
      "a--b--e--h--[k|]"
    }
  }

  func test_throwing() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdef^hijk|"
      $0.inputs[0]._throttle(for: .steps(2), clock: $0.clock)
      "a-c-e-^"
    }
  }

  func test_throwing_leading_edge() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdef^hijk|"
      $0.inputs[0]._throttle(for: .steps(2), clock: $0.clock, latest: false)
      "a-b-d-^"
    }
  }

  func test_emission_2_rate_1() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "-a-b-c-d-e-f-g-h-i-j-k-|"
      $0.inputs[0]._throttle(for: .steps(1), clock: $0.clock)
      "-a-b-c-d-e-f-g-h-i-j-k-|"
    }
  }

  func test_emission_2_rate_2() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "-a-b-c-d-e-f-g-h-i-j-k-|"
      $0.inputs[0]._throttle(for: .steps(2), clock: $0.clock)
      "-a-b-c-d-e-f-g-h-i-j-k-|"
    }
  }

  func test_emission_3_rate_2() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "--a--b--c--d--e--f--g|"
      $0.inputs[0]._throttle(for: .steps(2), clock: $0.clock)
      "--a--b--c--d--e--f--g|"
    }
  }

  func test_emission_2_rate_3() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "-a-b-c-d-e-f-g-h-i-j-k-|"
      $0.inputs[0]._throttle(for: .steps(3), clock: $0.clock)
      "-a---c---e---g---i---k-|"
    }
  }

  func test_trailing_delay_without_latest() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijkl|"
      $0.inputs[0]._throttle(for: .steps(3), clock: $0.clock, latest: false)
      "a--b--e--h--[k|]"
    }
  }

  func test_trailing_delay_with_latest() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "abcdefghijkl|"
      $0.inputs[0]._throttle(for: .steps(3), clock: $0.clock, latest: true)
      "a--d--g--j--[l|]"
    }
  }
  #endif
}

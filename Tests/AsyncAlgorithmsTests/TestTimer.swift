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

final class TestTimer: XCTestCase {
  func test_tick1() {
    marbleDiagram {
      AsyncTimerSequence(interval: .steps(1), clock: $0.clock).map { _ in "x" }
      "xxxxxxx[;|]"
    }
  }
  
  func test_tick2() {
    marbleDiagram {
      AsyncTimerSequence(interval: .steps(2), clock: $0.clock).map { _ in "x" }
      "-x-x-x-[;|]"
    }
  }
  
  func test_tick3() {
    marbleDiagram {
      AsyncTimerSequence(interval: .steps(3), clock: $0.clock).map { _ in "x" }
      "--x--x-[;|]"
    }
  }
}

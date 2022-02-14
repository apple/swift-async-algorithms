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

final class TestMarbleDiagram: XCTestCase {
  func test_diagram() {
    marbleDiagram {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C---|"
    }
  }
  
  func test_diagram_space_noop() {
    marbleDiagram {
      "    a -- b --  c       ---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "    A- - B - - C   -  --  |     "
    }
  }
  
  func test_diagram_failure_mismatch_value() {
    expectFailures(["expected \"X\" but got \"C\" at tick 6"])
    marbleDiagram {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--X---|"
    }
  }
  
  func test_diagram_failure_value_for_finish() {
    expectFailures(["expected finish but got \"C\" at tick 6",
                    "unexpected finish at tick 10"])
    marbleDiagram {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--|"
    }
  }
  
  func test_diagram_failure_finish_for_value() {
    expectFailures(["expected \"C\" but got finish at tick 6",
                    "expected finish at tick 7"])
    marbleDiagram {
      "a--b--|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }
  
  func test_diagram_failure_finish_for_error() {
    expectFailures(["expected failure but got finish at tick 6"])
    marbleDiagram {
      "a--b--|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }
  
  func test_diagram_failure_error_for_finish() {
    expectFailures(["expected finish but got failure at tick 6"])
    marbleDiagram {
      "a--b--^"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--|"
    }
  }
  
  func test_diagram_failure_value_for_error() {
    expectFailures(["expected failure but got \"C\" at tick 6",
                    "unexpected finish at tick 7"])
    marbleDiagram {
      "a--b--c|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }
  
  func test_diagram_failure_error_for_value() {
    expectFailures(["expected \"C\" but got failure at tick 6",
                    "expected finish at tick 7"])
    marbleDiagram {
      "a--b--^"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }
  
  func test_diagram_failure_expected_value() {
    expectFailures(["expected \"C\" at tick 6",
                    "unexpected finish at tick 7"])
    marbleDiagram {
      "a--b---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }
  
  func test_diagram_failure_expected_failure() {
    expectFailures(["expected failure at tick 6",
                    "unexpected finish at tick 7"])
    marbleDiagram {
      "a--b---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }
  
  func test_diagram_failure_unexpected_value() {
    expectFailures(["unexpected \"C\" at tick 6"])
    marbleDiagram {
      "a--b--c|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B---|"
    }
  }
  
  func test_diagram_failure_unexpected_failure() {
    expectFailures(["unexpected failure at tick 6",
                    "expected finish at tick 7"])
    marbleDiagram {
      "a--b--^|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B---|"
    }
  }
}

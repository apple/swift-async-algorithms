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

final class TestSwitchToLatest: XCTestCase {
  func test_completionOfInnerFirst() {
    validate { diagram in
      "x--y----|"
      "--a--c|"
      "----b|"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        switch value {
        case "x": return diagram.inputs[1]
        case "y": return diagram.inputs[2]
        default: fatalError()
        }
      }.switchToLatest()
      "--a-b---|"
    }
  }
  
  func test_completionOfOuterFirst() {
    validate { diagram in
      "x--y|----"
      "--a--c|"
      "----b---d|"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        switch value {
        case "x": return diagram.inputs[1]
        case "y": return diagram.inputs[2]
        default: fatalError()
        }
      }.switchToLatest()
      "--a-b---d|"
    }
  }
  
  func test_completionOfOuterFirst_2() {
    validate { diagram in
      "x---y---z|"
      "--ab|"
      "------cd|"
      "----------ef|"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        switch value {
        case "x": return diagram.inputs[1]
        case "y": return diagram.inputs[2]
        case "z": return diagram.inputs[3]
        default: fatalError()
        }
      }.switchToLatest()
      "--ab--cd--ef|"
    }
  }
  
  func test_errorFromOuterFirst() {
    validate { diagram in
      "a^----"
      "---a|-"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        return diagram.inputs[1]
      }.switchToLatest()
      "-^----"
    }
  }
  
  func test_errorFromOuterAfterValueFromInner() {
    validate { diagram in
      "x--y-^----"
      "--a--c|"
      "----b---d|"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        switch value {
        case "x": return diagram.inputs[1]
        case "y": return diagram.inputs[2]
        default: fatalError()
        }
      }.switchToLatest()
      "--a-b^----"
    }
  }
  
  func test_errorFromInnerFirst() {
    validate { diagram in
      "a----|"
      "--^---"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        return diagram.inputs[1]
      }.switchToLatest()
      "--^---"
    }
  }
  
  func test_errorFromInnerAfterValueFromInner() {
    validate { diagram in
      "x--y--|"
      "--a--c|"
      "----b^--d|"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        switch value {
        case "x": return diagram.inputs[1]
        case "y": return diagram.inputs[2]
        default: fatalError()
        }
      }.switchToLatest()
      "--a-b^----"
    }
  }
  
  func test_errorFromInnerAfterSwitchIsIgnored() {
    validate { diagram in
      "x--y--|"
      "--a-^"
      "----b---d|"
      diagram.inputs[0].map { value -> AsyncSequenceValidationDiagram.Input in
        switch value {
        case "x": return diagram.inputs[1]
        case "y": return diagram.inputs[2]
        default: fatalError()
        }
      }.switchToLatest()
      "--a-b---d|"
    }
  }
  
  func test_completionWithNoInnersProduced() {
    validate {
      "-----|"
      $0.inputs[0].map { _ in [String]().async }.switchToLatest()
      "-----|"
    }
  }
  
  func test_failureWithNoInnersProduced() {
    validate {
      "-----^"
      $0.inputs[0].map { _ in [String]().async }.switchToLatest()
      "-----^"
    }
  }
  
  func test_switching() {
    validate { diagram in
      "a--b--c--|"
      "aaaaaaa|"
      "---bbbbb|"
      "------ccc|"
      diagram.inputs[0].map { input -> AsyncSequenceValidationDiagram.Input in
        switch input {
        case "a": return diagram.inputs[1]
        case "b": return diagram.inputs[2]
        case "c": return diagram.inputs[3]
        default:
          fatalError()
        }
      }.switchToLatest()
      "aaabbbccc|"
    }
  }
}

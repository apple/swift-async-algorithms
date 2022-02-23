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

final class TestValidationDiagram: XCTestCase {
  func test_diagram() {
    validate {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C---|"
    }
  }
  
  func test_diagram_space_noop() {
    validate {
      "    a -- b --  c       ---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "    A- - B - - C   -  --  |     "
    }
  }
  
  func test_diagram_string_input() {
    validate {
      "'foo''bar''baz'|"
      $0.inputs[0].map { $0.first.map { String($0) } ?? "X" }
      "fbb|"
    }
  }
  
  func test_diagram_string_input_expectation() {
    validate {
      "'foo''bar''baz'|"
      $0.inputs[0]
      "'foo''bar''baz'|"
    }
  }
  
  func test_diagram_string_dsl_contents() {
    validate {
      "'foo-''bar^''baz|'|"
      $0.inputs[0]
      "'foo-''bar^''baz|'|"
    }
  }
  
  func test_diagram_grouping_source() {
    validate {
      "[abc]def|"
      $0.inputs[0]
      "[abc]def|"
    }
  }
  
  func test_diagram_groups_of_one() {
    validate {
      " a  b  c def|"
      $0.inputs[0]
      "[a][b][c]def|"
    }
  }
  
  func test_diagram_emoji() {
    struct EmojiTokens: AsyncSequenceValidationTheme {
      func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token {
        switch character {
        case "➖": return .step
        case "❗️": return .error
        case "❌": return .finish
        case "➡️": return .beginValue
        case "⬅️": return .endValue
        case " ": return .skip
        default: return .value(String(character))
        }
      }
    }
    
    validate(theme: EmojiTokens()) {
      "➖🔴➖🟠➖🟡➖🟢➖❌"
      $0.inputs[0]
      "➖🔴➖🟠➖🟡➖🟢➖❌"
    }
  }
  
  func test_cancel_event() {
    validate {
      "a--b- -  c--|"
      $0.inputs[0]
      "a--b-[;|]"
    }
  }
  
  func test_diagram_failure_mismatch_value() {
    expectFailures(["expected \"X\" but got \"C\" at tick 6"])
    validate {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--X---|"
    }
  }
  
  func test_diagram_failure_value_for_finish() {
    expectFailures(["expected finish but got \"C\" at tick 6",
                    "unexpected finish at tick 10"])
    validate {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--|"
    }
  }
  
  func test_diagram_failure_finish_for_value() {
    expectFailures(["expected \"C\" but got finish at tick 6",
                    "expected finish at tick 7"])
    validate {
      "a--b--|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }
  
  func test_diagram_failure_finish_for_error() {
    expectFailures(["expected failure but got finish at tick 6"])
    validate {
      "a--b--|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }
  
  func test_diagram_failure_error_for_finish() {
    expectFailures(["expected finish but got failure at tick 6"])
    validate {
      "a--b--^"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--|"
    }
  }
  
  func test_diagram_failure_value_for_error() {
    expectFailures(["expected failure but got \"C\" at tick 6",
                    "unexpected finish at tick 7"])
    validate {
      "a--b--c|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }
  
  func test_diagram_failure_error_for_value() {
    expectFailures(["expected \"C\" but got failure at tick 6",
                    "expected finish at tick 7"])
    validate {
      "a--b--^"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }
  
  func test_diagram_failure_expected_value() {
    expectFailures(["expected \"C\" at tick 6",
                    "unexpected finish at tick 7"])
    validate {
      "a--b---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }
  
  func test_diagram_failure_expected_failure() {
    expectFailures(["expected failure at tick 6",
                    "unexpected finish at tick 7"])
    validate {
      "a--b---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }
  
  func test_diagram_failure_unexpected_value() {
    expectFailures(["unexpected \"C\" at tick 6"])
    validate {
      "a--b--c|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B---|"
    }
  }
  
  func test_diagram_failure_unexpected_failure() {
    expectFailures(["unexpected failure at tick 6",
                    "expected finish at tick 7"])
    validate {
      "a--b--^|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B---|"
    }
  }
  
  func test_diagram_parse_failure_unbalanced_group() {
    expectFailures(["validation diagram unbalanced grouping"])
    validate {
      " ab|"
      $0.inputs[0]
      "[ab|"
    }
  }
  
  func test_diagram_parse_failure_nested_group() {
    expectFailures(["validation diagram nested grouping"])
    validate {
      "  ab|"
      $0.inputs[0]
      "[[ab|"
    }
  }
  
  func test_diagram_parse_failure_step_in_group() {
    expectFailures(["validation diagram step symbol in group"])
    validate {
      "  ab|"
      $0.inputs[0]
      "[a-]b|"
    }
  }
  
  func test_diagram_specification_produce_past_end() {
    expectFailures(["specification violation got \"d\" after iteration terminated at tick 9"])
    validate {
      "a--b--c--|"
      $0.inputs[0].violatingSpecification(returningPastEndIteration: "d")
      "a--b--c--|"
    }
  }
  
  func test_diagram_specification_throw_past_end() {
    expectFailures(["specification violation got failure after iteration terminated at tick 9"])
    validate {
      "a--b--c--|"
      $0.inputs[0].violatingSpecification(throwingPastEndIteration: Failure())
      "a--b--c--|"
    }
  }
}

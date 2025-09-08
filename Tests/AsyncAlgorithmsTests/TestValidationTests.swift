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

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)

import AsyncAlgorithms
import AsyncSequenceValidation
@testable import AsyncAlgorithms_XCTest

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
        case "⏳": return .delayNext
        case " ": return .skip
        default: return .value(String(character))
        }
      }

      func description(for token: AsyncSequenceValidationDiagram.Token) -> String {
        switch token {
        case .step: return "➖"
        case .error: return "❗️"
        case .finish: return "❌"
        case .cancel: return ""
        case .delayNext: return "⏳"
        case .beginValue: return "➡️"
        case .endValue: return "⬅️"
        case .beginGroup: return ""
        case .endGroup: return ""
        case .skip: return " "
        case .value(let value): return value
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
    validate(expectedFailures: ["expected \"X\" but got \"C\" at tick 6"]) {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--X---|"
    }
  }

  func test_diagram_failure_value_for_finish() {
    validate(expectedFailures: [
      "expected finish but got \"C\" at tick 6",
      "unexpected finish at tick 10",
    ]) {
      "a--b--c---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--|"
    }
  }

  func test_diagram_failure_finish_for_value() {
    validate(expectedFailures: [
      "expected \"C\" but got finish at tick 6",
      "expected finish at tick 7",
    ]) {
      "a--b--|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }

  func test_diagram_failure_finish_for_error() {
    validate(expectedFailures: ["expected failure but got finish at tick 6"]) {
      "a--b--|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }

  func test_diagram_failure_error_for_finish() {
    validate(expectedFailures: ["expected finish but got failure at tick 6"]) {
      "a--b--^"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--|"
    }
  }

  func test_diagram_failure_value_for_error() {
    validate(expectedFailures: [
      "expected failure but got \"C\" at tick 6",
      "unexpected finish at tick 7",
    ]) {
      "a--b--c|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }

  func test_diagram_failure_error_for_value() {
    validate(expectedFailures: [
      "expected \"C\" but got failure at tick 6",
      "expected finish at tick 7",
    ]) {
      "a--b--^"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }

  func test_diagram_failure_expected_value() {
    validate(expectedFailures: ["expected \"C\" at tick 6"]) {
      "a--b---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--C|"
    }
  }

  func test_diagram_failure_expected_failure() {
    validate(expectedFailures: [
      "expected failure at tick 6",
      "unexpected finish at tick 7",
    ]) {
      "a--b---|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B--^"
    }
  }

  func test_diagram_failure_unexpected_value() {
    validate(expectedFailures: ["unexpected \"C\" at tick 6"]) {
      "a--b--c|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B---|"
    }
  }

  func test_diagram_failure_unexpected_failure() {
    validate(expectedFailures: [
      "unexpected failure at tick 6",
      "expected finish at tick 7",
    ]) {
      "a--b--^|"
      $0.inputs[0].map { item in await Task { item.capitalized }.value }
      "A--B---|"
    }
  }

  func test_diagram_parse_failure_unbalanced_group() {
    validate(expectedFailures: ["validation diagram unbalanced grouping"]) {
      " ab|"
      $0.inputs[0]
      "[ab|"
    }
  }

  func test_diagram_parse_failure_unbalanced_group_input() {
    validate(expectedFailures: ["validation diagram unbalanced grouping"]) {
      "[ab|"
      $0.inputs[0]
      " ab|"
    }
  }

  func test_diagram_parse_failure_nested_group() {
    validate(expectedFailures: ["validation diagram nested grouping"]) {
      "  ab|"
      $0.inputs[0]
      "[[ab|"
    }
  }

  func test_diagram_parse_failure_nested_group_input() {
    validate(expectedFailures: ["validation diagram nested grouping"]) {
      "[[ab|"
      $0.inputs[0]
      "  ab|"
    }
  }

  func test_diagram_parse_failure_step_in_group() {
    validate(expectedFailures: ["validation diagram step symbol in group"]) {
      "  ab|"
      $0.inputs[0]
      "[a-]b|"
    }
  }

  func test_diagram_parse_failure_step_in_group_input() {
    validate(expectedFailures: ["validation diagram step symbol in group"]) {
      "[a-]b|"
      $0.inputs[0]
      "  ab|"
    }
  }

  func test_diagram_specification_produce_past_end() {
    validate(expectedFailures: ["specification violation got \"d\" after iteration terminated at tick 9"]) {
      "a--b--c--|"
      $0.inputs[0].violatingSpecification(returningPastEndIteration: "d")
      "a--b--c--|"
    }
  }

  func test_diagram_specification_throw_past_end() {
    validate(expectedFailures: ["specification violation got failure after iteration terminated at tick 9"]) {
      "a--b--c--|"
      $0.inputs[0].violatingSpecification(throwingPastEndIteration: Failure())
      "a--b--c--|"
    }
  }

  func test_delayNext() {
    validate {
      "xxx---   |"
      $0.inputs[0]
      "x,,,,[xx]|"
    }
  }

  func test_delayNext_initialDelay() {
    validate {
      "xxx    |"
      $0.inputs[0]
      ",,[xxx]|"
    }
  }

  func test_delayNext_into_emptyTick() throws {
    guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
      throw XCTSkip("Skipped due to Clock/Instant/Duration availability")
    }
    validate {
      "xx|"
      LaggingAsyncSequence($0.inputs[0], delayBy: .steps(3), using: $0.clock)
      ",,,---x--[x|]"
    }
  }

  func test_values_one_at_a_time_after_delay() {
    validate {
      "xxx|"
      $0.inputs[0]
      ",,,[x,][x,][x,]|"
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct LaggingAsyncSequence<Base: AsyncSequence, C: Clock>: AsyncSequence {
  typealias Element = Base.Element

  struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
    let delay: C.Instant.Duration
    let clock: C
    mutating func next() async throws -> Element? {
      guard let value = try await base.next() else {
        return nil
      }
      try await clock.sleep(until: clock.now.advanced(by: delay), tolerance: nil)
      return value
    }
  }

  func makeAsyncIterator() -> Iterator {
    return Iterator(base: base.makeAsyncIterator(), delay: delay, clock: clock)
  }

  let base: Base
  let delay: C.Instant.Duration
  let clock: C
  init(_ base: Base, delayBy delay: C.Instant.Duration, using clock: C) {
    self.base = base
    self.delay = delay
    self.clock = clock
  }
}

#endif

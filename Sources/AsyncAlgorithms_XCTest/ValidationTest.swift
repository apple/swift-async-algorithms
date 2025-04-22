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

extension XCTestCase {
  func recordFailure(_ description: String, system: Bool = false, at location: AsyncSequenceValidation.SourceLocation) {
    #if canImport(Darwin)
    let context = XCTSourceCodeContext(
      location: XCTSourceCodeLocation(filePath: location.file.description, lineNumber: Int(location.line))
    )
    let issue = XCTIssue(
      type: system ? .system : .assertionFailure,
      compactDescription: description,
      detailedDescription: nil,
      sourceCodeContext: context,
      associatedError: nil,
      attachments: []
    )
    record(issue)
    #else
    XCTFail(description, file: location.file, line: location.line)
    #endif
  }

  @available(AsyncAlgorithms 1.0, *)
  func validate<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(
    theme: Theme,
    expectedFailures: Set<String>,
    @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    var expectations = expectedFailures
    var result: AsyncSequenceValidationDiagram.ExpectationResult?
    var failures = [AsyncSequenceValidationDiagram.ExpectationFailure]()
    let baseLoc = AsyncSequenceValidation.SourceLocation(file: file, line: line)
    var accountedFailures = [AsyncSequenceValidationDiagram.ExpectationFailure]()
    do {
      (result, failures) = try AsyncSequenceValidationDiagram.test(theme: theme, build)
      for failure in failures {
        if expectations.remove(failure.description) == nil {
          recordFailure(failure.description, at: failure.specification?.location ?? baseLoc)
        } else {
          accountedFailures.append(failure)
        }
      }
    } catch {
      if expectations.remove("\(error)") == nil {
        recordFailure("\(error)", system: true, at: (error as? SourceFailure)?.location ?? baseLoc)
      }
    }
    // If no failures were expected and the result reconstitues to something different
    // than what was expected, dump that out as a failure for easier diagnostics, this
    // likely should be done via attachments but that does not display inline code
    // nicely. Ideally we would want to have this display as a runtime warning but those
    // do not have source line attribution; for now XCTFail is good enough.
    if let result = result, expectedFailures.count == 0 {
      let expected = result.reconstituteExpected(theme: theme)
      let actual = result.reconstituteActual(theme: theme)
      if expected != actual {
        XCTFail("Validation failure:\nExpected:\n\(expected)\nActual:\n\(actual)", file: file, line: line)
      }
    }
    // any remaining expectations are failures that were expected but did not happen
    for expectation in expectations {
      XCTFail("Expected failure: \(expectation) did not occur.", file: file, line: line)
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  func validate<Test: AsyncSequenceValidationTest>(
    expectedFailures: Set<String>,
    @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    validate(theme: .ascii, expectedFailures: expectedFailures, build, file: file, line: line)
  }

  @available(AsyncAlgorithms 1.0, *)
  public func validate<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(
    theme: Theme,
    @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    validate(theme: theme, expectedFailures: [], build, file: file, line: line)
  }

  @available(AsyncAlgorithms 1.0, *)
  public func validate<Test: AsyncSequenceValidationTest>(
    @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    validate(theme: .ascii, expectedFailures: [], build, file: file, line: line)
  }
}

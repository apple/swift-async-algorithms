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
  func recordFailure(_ description: String, detail: String? = nil, system: Bool = false, at location: AsyncSequenceValidation.SourceLocation) {
#if canImport(Darwin)
    let context = XCTSourceCodeContext(location: XCTSourceCodeLocation(filePath: location.file.description, lineNumber: Int(location.line)))
    let issue = XCTIssue(type: system ? .system : .assertionFailure, compactDescription: description, detailedDescription: detail, sourceCodeContext: context, associatedError: nil, attachments: [])
    record(issue)
#else
    XCTFail(description, file: location.file, line: location.line)
#endif
  }
  
  func validate<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(theme: Theme, expectedFailures: Set<String>, @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    var expectations = expectedFailures
    let baseLoc = AsyncSequenceValidation.SourceLocation(file: file, line: line)
    do {
      let (result, failures) = try AsyncSequenceValidationDiagram.test(theme: theme, build)
      var detail: String?
      if failures.count > 0 {
        detail = """
        Expected
        \(result.reconstituteExpected(theme: theme))
        Actual
        \(result.reconstituteActual(theme: theme))
        """
        print("Expected")
        print(result.reconstituteExpected(theme: theme))
        print("Actual")
        print(result.reconstituteActual(theme: theme))
      }
      for failure in failures {
        if expectations.remove(failure.description) == nil {
          recordFailure(failure.description, detail: detail, at: failure.specification?.location ?? baseLoc)
        }
      }
    } catch {
      if expectations.remove("\(error)") == nil {
        recordFailure("\(error)", system: true, at: (error as? SourceFailure)?.location ?? baseLoc)
      }
    }
    // any remaining expectations are failures that were expected but did not happen
    for expectation in expectations {
      XCTFail("Expected failure: \(expectation) did not occur.", file: file, line: line)
    }
  }
  
  func validate<Test: AsyncSequenceValidationTest>(expectedFailures: Set<String>, @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    validate(theme: .ascii, expectedFailures: expectedFailures, build, file: file, line: line)
  }
  
  public func validate<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(theme: Theme, @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    validate(theme: theme, expectedFailures: [], build, file: file, line: line)
  }
  
  public func validate<Test: AsyncSequenceValidationTest>(@AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    validate(theme: .ascii, expectedFailures: [], build, file: file, line: line)
  }
}

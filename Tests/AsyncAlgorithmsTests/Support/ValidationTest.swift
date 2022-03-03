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
  public func validate<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(theme: Theme, @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    let location = XCTSourceCodeLocation(filePath: file.description, lineNumber: Int(line))
    let context = XCTSourceCodeContext(location: location)
    do {
      let (result, failures) = try AsyncSequenceValidationDiagram.test(theme: theme, build)
      if failures.count > 0 {
        print("Expected")
        print(result.reconstituteExpected(theme: theme))
        print("Actual")
        print(result.reconstituteActual(theme: theme))
      }
      for failure in failures {
        let issue = XCTIssue(type: .assertionFailure, compactDescription: failure.description, detailedDescription: nil, sourceCodeContext: context, associatedError: nil, attachments: [])
        record(issue)
      }
    } catch {
      let issue = XCTIssue(type: .system, compactDescription: "\(error)", detailedDescription: nil, sourceCodeContext: context, associatedError: nil, attachments: [])
      record(issue)
    }
  }
  
  public func validate<Test: AsyncSequenceValidationTest>(@AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    validate(theme: .ascii, build, file: file, line: line)
  }
}

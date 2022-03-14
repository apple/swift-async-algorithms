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
    let baseLocation = XCTSourceCodeLocation(filePath: file.description, lineNumber: Int(line))
    let baseContext = XCTSourceCodeContext(location: baseLocation)
    do {
      let (result, failures) = try AsyncSequenceValidationDiagram.test(theme: theme, build)
      if failures.count > 0 {
        print("Expected")
        print(result.reconstituteExpected(theme: theme))
        print("Actual")
        print(result.reconstituteActual(theme: theme))
      }
      for failure in failures {
        if let specification = failure.specification {
          let location = XCTSourceCodeLocation(filePath: specification.location.file.description, lineNumber: Int(specification.location.line))
          let context = XCTSourceCodeContext(location: location)
          let issue = XCTIssue(type: .assertionFailure, compactDescription: failure.description, detailedDescription: nil, sourceCodeContext: context, associatedError: nil, attachments: [])
          record(issue)
        } else {
          let issue = XCTIssue(type: .assertionFailure, compactDescription: failure.description, detailedDescription: nil, sourceCodeContext: baseContext, associatedError: nil, attachments: [])
          record(issue)
        }
      }
    } catch {
      if let sourceFailure = error as? SourceFailure {
        let location = XCTSourceCodeLocation(filePath: sourceFailure.location.file.description, lineNumber: Int(sourceFailure.location.line))
        let context = XCTSourceCodeContext(location: location)
        let issue = XCTIssue(type: .system, compactDescription: "\(error)", detailedDescription: nil, sourceCodeContext: context, associatedError: nil, attachments: [])
        record(issue)
      } else {
        let issue = XCTIssue(type: .system, compactDescription: "\(error)", detailedDescription: nil, sourceCodeContext: baseContext, associatedError: nil, attachments: [])
        record(issue)
      }
    }
  }
  
  public func validate<Test: AsyncSequenceValidationTest>(@AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    validate(theme: .ascii, build, file: file, line: line)
  }
}

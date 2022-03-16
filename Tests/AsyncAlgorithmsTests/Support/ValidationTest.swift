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
#if canImport(Darwin)
    let baseLocation = XCTSourceCodeLocation(filePath: file.description, lineNumber: Int(line))
    let baseContext = XCTSourceCodeContext(location: baseLocation)
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
        if let specification = failure.specification {
          let location = XCTSourceCodeLocation(filePath: specification.location.file.description, lineNumber: Int(specification.location.line))
          let context = XCTSourceCodeContext(location: location)
          let issue = XCTIssue(type: .assertionFailure, compactDescription: failure.description, detailedDescription: detail, sourceCodeContext: context, associatedError: nil, attachments: [])
          record(issue)
        } else {
          let issue = XCTIssue(type: .assertionFailure, compactDescription: failure.description, detailedDescription: detail, sourceCodeContext: baseContext, associatedError: nil, attachments: [])
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
#else
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
          XCTFail(failure.description, file: specification.location.file, line: specification.location.line)
        } else {
          XCTFail(failure.description, file: file, line: line)
        }
      }
    } catch {
      if let sourceFailure = error as? SourceFailure {
        XCTFail("\(sourceFailure)", file: sourceFailure.location.file, line: sourceFailure.location.line)
      } else {
        XCTFail("\(error)", file: file, line: line)
      }
    }
#endif
  }
  
  public func validate<Test: AsyncSequenceValidationTest>(@AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    validate(theme: .ascii, build, file: file, line: line)
  }
}

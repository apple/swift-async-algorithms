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

extension XCTestCase {
  public func marbleDiagram<Test: MarbleDiagramTest, Theme: MarbleDiagramTheme>(theme: Theme, @MarbleDiagram _ build: (inout MarbleDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    let location = XCTSourceCodeLocation(filePath: file.description, lineNumber: Int(line))
    let context = XCTSourceCodeContext(location: location)
    do {
      let (result, failures) = try MarbleDiagram.test(theme: theme, build)
      if failures.count > 0 {
        print("Expected")
        for (when, result) in result.expected {
          print(when, result)
        }
        print("Actual")
        for (when, result) in result.actual {
          print(when, result)
        }
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
  
  public func marbleDiagram<Test: MarbleDiagramTest>(@MarbleDiagram _ build: (inout MarbleDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    marbleDiagram(theme: .ascii, build, file: file, line: line)
  }
}

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

import Foundation
import XCTest

extension XCTestCase {
  
  /// Creates a new async expectation with an associated description.
  ///
  /// Use this method to create ``AsyncExpectation`` instances that can be
  /// fulfilled when asynchronous tasks in your tests complete.
  ///
  /// To fulfill an expectation that was created with `asyncExpectation(description:)`,
  /// call the expectation's `fulfill()` method when the asynchronous task in your
  /// test has completed.
  ///
  /// - Parameters:
  ///   - description: A string to display in the test log for this expectation, to help diagnose failures.
  ///   - isInverted: Indicates that the expectation is not intended to happen.
  ///   - expectedFulfillmentCount: The number of times fulfill() must be called before the expectation is completely fulfilled. (default = 1)
  public func asyncExpectation(description: String,
                               isInverted: Bool = false,
                               expectedFulfillmentCount: Int = 1) -> AsyncExpectation {
    AsyncExpectation(description: description,
                     isInverted: isInverted,
                     expectedFulfillmentCount: expectedFulfillmentCount)
  }
  
  /// Waits for the test to fulfill a set of expectations within a specified time.
  /// - Parameters:
  ///   - expectations: An array of async expectations that must be fulfilled.
  ///   - timeout: The number of seconds within which all expectations must be fulfilled.
  @MainActor
  public func waitForExpectations(_ expectations: [AsyncExpectation],
                                  timeout: Double = 1.0,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) async {
    await AsyncExpectation.waitForExpectations(expectations,
                                               timeout: timeout,
                                               file: file,
                                               line: line)
  }
  
}

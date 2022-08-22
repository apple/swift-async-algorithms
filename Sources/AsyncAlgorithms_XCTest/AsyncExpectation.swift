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

extension Task where Success == Never, Failure == Never {
  static func sleep(seconds: Double) async throws {
    let nanoseconds = UInt64(seconds * Double(NSEC_PER_SEC))
    try await Task.sleep(nanoseconds: nanoseconds)
  }
}

public actor AsyncExpectation {
  enum State {
    case pending
    case fulfilled
    case timedOut
  }
  public typealias AsyncExpectationContinuation = CheckedContinuation<Void, Error>
  public let expectationDescription: String
  public let isInverted: Bool
  public let expectedFulfillmentCount: Int
  
  private var fulfillmentCount: Int = 0
  private var continuation: AsyncExpectationContinuation?
  private var state: State = .pending
  
  public var isFulfilled: Bool {
    state == .fulfilled
  }
  
  public init(description: String,
              isInverted: Bool = false,
              expectedFulfillmentCount: Int = 1) {
    expectationDescription = description
    self.isInverted = isInverted
    self.expectedFulfillmentCount = expectedFulfillmentCount
  }
  
  /// Marks the expectation as having been met.
  ///
  /// It is an error to call this method on an expectation that has already been fulfilled,
  /// or when the test case that vended the expectation has already completed.
  public func fulfill(file: StaticString = #filePath, line: UInt = #line) {
    guard state != .fulfilled else { return }
    
    if isInverted {
      if state != .timedOut {
        XCTFail("Inverted expectation fulfilled: \(expectationDescription)", file: file, line: line)
        state = .fulfilled
        finish()
      }
      return
    }
    
    fulfillmentCount += 1
    if fulfillmentCount == expectedFulfillmentCount {
      state = .fulfilled
      finish()
    }
  }
  
  @MainActor
  public static func waitForExpectations(_ expectations: [AsyncExpectation],
                                         timeout: Double = 1.0,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) async {
    guard !expectations.isEmpty else { return }
    
    // check if all expectations are already satisfied and skip sleeping
    var count = 0
    for exp in expectations {
      if await exp.isFulfilled {
        count += 1
      }
    }
    if count == expectations.count {
      return
    }
    
    let timeout = Task {
      do {
        try await Task.sleep(seconds: timeout)
        for exp in expectations {
          await exp.timeOut(file: file, line: line)
        }
      } catch {}
    }
    
    await waitUsingTaskGroup(expectations)
    
    timeout.cancel()
  }
  
  private static func waitUsingTaskGroup(_ expectations: [AsyncExpectation]) async {
    await withTaskGroup(of: Void.self) { group in
      for exp in expectations {
        group.addTask {
          do {
            try await exp.wait()
          } catch {}
        }
      }
    }
  }
  
  internal nonisolated func wait() async throws {
    try await withTaskCancellationHandler(handler: {
      Task {
        await cancel()
      }
    }, operation: {
      try await handleWait()
    })
  }
  
  internal func timeOut(file: StaticString = #filePath,
                        line: UInt = #line) async {
    if isInverted {
      state = .timedOut
    } else if state != .fulfilled {
      state = .timedOut
      XCTFail("Expectation timed out: \(expectationDescription)", file: file, line: line)
    }
    finish()
  }
  
  private func handleWait() async throws {
    if state == .fulfilled {
      return
    } else {
      try await withCheckedThrowingContinuation { (continuation: AsyncExpectationContinuation) in
        self.continuation = continuation
      }
    }
  }
  
  private func cancel() {
    continuation?.resume(throwing: CancellationError())
    continuation = nil
  }
  
  private func finish() {
    continuation?.resume(returning: ())
    continuation = nil
  }
  
}

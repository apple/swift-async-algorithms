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
  
  public init(description: String,
              isInverted: Bool = false,
              expectedFulfillmentCount: Int = 1) {
    expectationDescription = description
    self.isInverted = isInverted
    self.expectedFulfillmentCount = expectedFulfillmentCount
  }
  
  public static func expectation(description: String,
                                 isInverted: Bool = false,
                                 expectedFulfillmentCount: Int = 1) -> AsyncExpectation {
    AsyncExpectation(description: description,
                     isInverted: isInverted,
                     expectedFulfillmentCount: expectedFulfillmentCount)
  }
  
  public func fulfill(file: StaticString = #filePath, line: UInt = #line) {
    guard state != .fulfilled else { return }
    
    guard !isInverted else {
      XCTFail("Inverted expectation fulfilled: \(expectationDescription)", file: file, line: line)
      finish()
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
                                         line: UInt = #line) async throws {
    guard !expectations.isEmpty else { return }
    
    // check if all expectations are already satisfied and skip sleeping
    var count = 0
    for exp in expectations {
      if await exp.state == .fulfilled {
        count += 1
      }
    }
    if count == expectations.count {
      return
    }
    
    let timeout = Task {
      try await Task.sleep(seconds: timeout)
      for exp in expectations {
        await exp.timeOut(file: file, line: line)
      }
    }
    
    await withThrowingTaskGroup(of: Void.self) { group in
      for exp in expectations {
        group.addTask {
          try await exp.wait()
        }
      }
    }
    
    timeout.cancel()
  }
  
  private func wait() async throws {
    try await withTaskCancellationHandler(handler: {
      Task {
        await cancel()
      }
    }, operation: {
      if state == .fulfilled {
        return
      } else {
        return try await withCheckedThrowingContinuation { (continuation: AsyncExpectationContinuation) in
          self.continuation = continuation
        }
      }
    })
  }
  
  private func timeOut(file: StaticString = #filePath,
                       line: UInt = #line) async {
    if state != .fulfilled && !isInverted {
      state = .timedOut
      XCTFail("Expectation timed out: \(expectationDescription)", file: file, line: line)
    }
    finish()
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

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

private enum _XCTAssertion {
  case equal
  case equalWithAccuracy
  case identical
  case notIdentical
  case greaterThan
  case greaterThanOrEqual
  case lessThan
  case lessThanOrEqual
  case notEqual
  case notEqualWithAccuracy
  case `nil`
  case notNil
  case unwrap
  case `true`
  case `false`
  case fail
  case throwsError
  case noThrow

  var name: String? {
    switch self {
    case .equal: return "XCTAssertEqual"
    case .equalWithAccuracy: return "XCTAssertEqual"
    case .identical: return "XCTAssertIdentical"
    case .notIdentical: return "XCTAssertNotIdentical"
    case .greaterThan: return "XCTAssertGreaterThan"
    case .greaterThanOrEqual: return "XCTAssertGreaterThanOrEqual"
    case .lessThan: return "XCTAssertLessThan"
    case .lessThanOrEqual: return "XCTAssertLessThanOrEqual"
    case .notEqual: return "XCTAssertNotEqual"
    case .notEqualWithAccuracy: return "XCTAssertNotEqual"
    case .`nil`: return "XCTAssertNil"
    case .notNil: return "XCTAssertNotNil"
    case .unwrap: return "XCTUnwrap"
    case .`true`: return "XCTAssertTrue"
    case .`false`: return "XCTAssertFalse"
    case .throwsError: return "XCTAssertThrowsError"
    case .noThrow: return "XCTAssertNoThrow"
    case .fail: return nil
    }
  }
}

private enum _XCTAssertionResult {
  case success
  case expectedFailure(String?)
  case unexpectedFailure(Swift.Error)

  var isExpected: Bool {
    switch self {
    case .unexpectedFailure(_): return false
    default: return true
    }
  }

  func failureDescription(_ assertion: _XCTAssertion) -> String {
    let explanation: String
    switch self {
    case .success: explanation = "passed"
    case .expectedFailure(let details?): explanation = "failed: \(details)"
    case .expectedFailure(_): explanation = "failed"
    case .unexpectedFailure(let error): explanation = "threw error \"\(error)\""
    }

    guard let name = assertion.name else {
      return explanation
    }
    return "\(name) \(explanation)"
  }
}

private func _XCTEvaluateAssertion(
  _ assertion: _XCTAssertion,
  message: () -> String,
  file: StaticString,
  line: UInt,
  expression: () throws -> _XCTAssertionResult
) {
  let result: _XCTAssertionResult
  do {
    result = try expression()
  } catch {
    result = .unexpectedFailure(error)
  }

  switch result {
  case .success:
    return
  default:
    XCTFail("\(result.failureDescription(assertion)) - \(message())", file: file, line: line)
  }
}

private func _XCTAssertEqual<T>(
  _ expression1: () throws -> T,
  _ expression2: () throws -> T,
  _ equal: (T, T) -> Bool,
  _ message: () -> String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  _XCTEvaluateAssertion(.equal, message: message, file: file, line: line) {
    let (value1, value2) = (try expression1(), try expression2())
    guard equal(value1, value2) else {
      return .expectedFailure("(\"\(value1)\") is not equal to (\"\(value2)\")")
    }
    return .success
  }
}

public func XCTAssertEqual<A: Equatable, B: Equatable>(
  _ expression1: @autoclosure () throws -> (A, B),
  _ expression2: @autoclosure () throws -> (A, B),
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  _XCTAssertEqual(expression1, expression2, { $0 == $1 }, message, file: file, line: line)
}

private func == <A: Equatable, B: Equatable>(_ lhs: [(A, B)], _ rhs: [(A, B)]) -> Bool {
  guard lhs.count == rhs.count else {
    return false
  }
  for (lhsElement, rhsElement) in zip(lhs, rhs) {
    if lhsElement != rhsElement {
      return false
    }
  }
  return true
}

public func XCTAssertEqual<A: Equatable, B: Equatable>(
  _ expression1: @autoclosure () throws -> [(A, B)],
  _ expression2: @autoclosure () throws -> [(A, B)],
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  _XCTAssertEqual(expression1, expression2, { $0 == $1 }, message, file: file, line: line)
}

public func XCTAssertEqual<A: Equatable, B: Equatable, C: Equatable>(
  _ expression1: @autoclosure () throws -> (A, B, C),
  _ expression2: @autoclosure () throws -> (A, B, C),
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  _XCTAssertEqual(expression1, expression2, { $0 == $1 }, message, file: file, line: line)
}

private func == <A: Equatable, B: Equatable, C: Equatable>(_ lhs: [(A, B, C)], _ rhs: [(A, B, C)]) -> Bool {
  guard lhs.count == rhs.count else {
    return false
  }
  for (lhsElement, rhsElement) in zip(lhs, rhs) {
    if lhsElement != rhsElement {
      return false
    }
  }
  return true
}

public func XCTAssertEqual<A: Equatable, B: Equatable, C: Equatable>(
  _ expression1: @autoclosure () throws -> [(A, B, C)],
  _ expression2: @autoclosure () throws -> [(A, B, C)],
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  _XCTAssertEqual(expression1, expression2, { $0 == $1 }, message, file: file, line: line)
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  file: StaticString = #file,
  line: UInt = #line,
  verify: (Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    XCTFail("Expression did not throw error", file: file, line: line)
  } catch {
    verify(error)
  }
}

class WaiterDelegate: NSObject, XCTWaiterDelegate {
  let state: ManagedCriticalState<UnsafeContinuation<Void, Never>?> = ManagedCriticalState(nil)

  init(_ continuation: UnsafeContinuation<Void, Never>) {
    state.withCriticalRegion { $0 = continuation }
  }

  func waiter(_ waiter: XCTWaiter, didFulfillInvertedExpectation expectation: XCTestExpectation) {
    resume()
  }

  func waiter(_ waiter: XCTWaiter, didTimeoutWithUnfulfilledExpectations unfulfilledExpectations: [XCTestExpectation]) {
    resume()
  }

  func waiter(
    _ waiter: XCTWaiter,
    fulfillmentDidViolateOrderingConstraintsFor expectation: XCTestExpectation,
    requiredExpectation: XCTestExpectation
  ) {
    resume()
  }

  func nestedWaiter(_ waiter: XCTWaiter, wasInterruptedByTimedOutWaiter outerWaiter: XCTWaiter) {

  }

  func resume() {
    let continuation = state.withCriticalRegion { continuation in
      defer { continuation = nil }
      return continuation
    }
    continuation?.resume()
  }
}

extension XCTestCase {
  @_disfavoredOverload
  func fulfillment(
    of expectations: [XCTestExpectation],
    timeout: TimeInterval,
    enforceOrder: Bool = false,
    file: StaticString = #file,
    line: Int = #line
  ) async {
    return await withUnsafeContinuation { continuation in
      let delegate = WaiterDelegate(continuation)
      let waiter = XCTWaiter(delegate: delegate)
      waiter.wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
      delegate.resume()
    }
  }
}

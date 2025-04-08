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

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram {
  public struct ExpectationResult: Sendable {
    public struct Event: Sendable {
      public var when: Clock.Instant
      public var result: Result<String?, Error>
      public var offset: String.Index
    }
    public var expected: [Event]
    public var actual: [(Clock.Instant, Result<String?, Error>)]

    func reconstitute<Theme: AsyncSequenceValidationTheme>(_ result: Result<String?, Error>, theme: Theme) -> String {
      var reconstituted = ""
      switch result {
      case .success(let value):
        if let value = value {
          if value.count > 1 {
            reconstituted += theme.description(for: .beginValue)
            reconstituted += theme.description(for: .value(value))
            reconstituted += theme.description(for: .endValue)
          } else {
            reconstituted += theme.description(for: .value(value))
          }
        } else {
          reconstituted += theme.description(for: .finish)
        }
      case .failure:
        reconstituted += theme.description(for: .error)
      }
      return reconstituted
    }

    func reconstitute<Theme: AsyncSequenceValidationTheme>(
      _ events: [Clock.Instant: [Result<String?, Error>]],
      theme: Theme,
      end: Clock.Instant
    ) -> String {
      var now = Clock.Instant(when: .steps(1))  // adjust for the offset index
      var reconstituted = ""
      while now <= end {
        if let results = events[now] {
          if results.count == 1 {
            reconstituted += reconstitute(results[0], theme: theme)
          } else {
            reconstituted += theme.description(for: .beginGroup)
            for result in results {
              reconstituted += reconstitute(result, theme: theme)
            }
            reconstituted += theme.description(for: .endGroup)
          }
        } else {
          reconstituted += theme.description(for: .step)
        }
        now = now.advanced(by: .steps(1))
      }
      return reconstituted
    }

    public func reconstituteExpected<Theme: AsyncSequenceValidationTheme>(theme: Theme) -> String {
      var events = [Clock.Instant: [Result<String?, Error>]]()
      var end: Clock.Instant = Clock.Instant(when: .zero)

      for expectation in expected {
        let when = expectation.when
        let result = expectation.result
        events[when, default: []].append(result)
        if when > end {
          end = when
        }
      }

      return reconstitute(events, theme: theme, end: end)
    }

    public func reconstituteActual<Theme: AsyncSequenceValidationTheme>(theme: Theme) -> String {
      var events = [Clock.Instant: [Result<String?, Error>]]()
      var end: Clock.Instant = Clock.Instant(when: .zero)

      for (when, result) in actual {
        events[when, default: []].append(result)
        if when > end {
          end = when
        }
      }

      return reconstitute(events, theme: theme, end: end)
    }
  }

  public struct ExpectationFailure: Sendable, CustomStringConvertible {
    public enum Kind: Sendable {
      case expectedFinishButGotValue(String)
      case expectedMismatch(String, String)
      case expectedValueButGotFinished(String)
      case expectedFailureButGotValue(Error, String)
      case expectedFailureButGotFinish(Error)
      case expectedValueButGotFailure(String, Error)
      case expectedFinishButGotFailure(Error)
      case expectedValue(String)
      case expectedFinish
      case expectedFailure(Error)
      case unexpectedValue(String)
      case unexpectedFinish
      case unexpectedFailure(Error)

      case specificationViolationGotValueAfterIteration(String)
      case specificationViolationGotFailureAfterIteration(Error)
    }
    public var when: Clock.Instant
    public var kind: Kind

    public var specification: Specification?
    public var index: String.Index?

    init(when: Clock.Instant, kind: Kind, specification: Specification? = nil, index: String.Index? = nil) {
      self.when = when
      self.kind = kind
      self.specification = specification
      self.index = index
    }

    var reason: String {
      switch kind {
      case .expectedFinishButGotValue(let actual):
        return "expected finish but got \"\(actual)\""
      case .expectedMismatch(let expected, let actual):
        return "expected \"\(expected)\" but got \"\(actual)\""
      case .expectedValueButGotFinished(let expected):
        return "expected \"\(expected)\" but got finish"
      case .expectedFailureButGotValue(_, let actual):
        return "expected failure but got \"\(actual)\""
      case .expectedFailureButGotFinish:
        return "expected failure but got finish"
      case .expectedValueButGotFailure(let expected, _):
        return "expected \"\(expected)\" but got failure"
      case .expectedFinishButGotFailure:
        return "expected finish but got failure"
      case .expectedValue(let expected):
        return "expected \"\(expected)\""
      case .expectedFinish:
        return "expected finish"
      case .expectedFailure:
        return "expected failure"
      case .unexpectedValue(let actual):
        return "unexpected \"\(actual)\""
      case .unexpectedFinish:
        return "unexpected finish"
      case .unexpectedFailure:
        return "unexpected failure"
      case .specificationViolationGotValueAfterIteration(let actual):
        return "specification violation got \"\(actual)\" after iteration terminated"
      case .specificationViolationGotFailureAfterIteration:
        return "specification violation got failure after iteration terminated"
      }
    }

    public var description: String {
      return reason + " at tick \(when.when.rawValue - 1)"
    }
  }
}

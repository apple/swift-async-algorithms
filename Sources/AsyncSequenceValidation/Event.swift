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
  struct Failure: Error, Equatable {}

  enum ParseFailure: Error, CustomStringConvertible, SourceFailure {
    case stepInGroup(String, String.Index, SourceLocation)
    case nestedGroup(String, String.Index, SourceLocation)
    case unbalancedNesting(String, String.Index, SourceLocation)

    var location: SourceLocation {
      switch self {
      case .stepInGroup(_, _, let location): return location
      case .nestedGroup(_, _, let location): return location
      case .unbalancedNesting(_, _, let location): return location
      }
    }

    var description: String {
      switch self {
      case .stepInGroup:
        return "validation diagram step symbol in group"
      case .nestedGroup:
        return "validation diagram nested grouping"
      case .unbalancedNesting:
        return "validation diagram unbalanced grouping"
      }
    }
  }

  enum Event {
    case value(String, String.Index)
    case failure(Error, String.Index)
    case finish(String.Index)
    case delayNext(String.Index)
    case cancel(String.Index)

    var results: [Result<String?, Error>] {
      switch self {
      case .value(let value, _): return [.success(value)]
      case .failure(let failure, _): return [.failure(failure)]
      case .finish: return [.success(nil)]
      case .delayNext: return []
      case .cancel: return []
      }
    }

    var index: String.Index {
      switch self {
      case .value(_, let index): return index
      case .failure(_, let index): return index
      case .finish(let index): return index
      case .delayNext(let index): return index
      case .cancel(let index): return index
      }
    }

    static func parse<Theme: AsyncSequenceValidationTheme>(
      _ dsl: String,
      theme: Theme,
      location: SourceLocation
    ) throws -> [(Clock.Instant, Event)] {
      var emissions = [(Clock.Instant, Event)]()
      var when = Clock.Instant(when: .steps(0))
      var string: String?
      var grouping = 0

      for index in dsl.indices {
        let ch = dsl[index]
        switch theme.token(dsl[index], inValue: string != nil) {
        case .step:
          if string == nil {
            guard grouping == 0 else {
              throw ParseFailure.stepInGroup(dsl, index, location)
            }
            when = when.advanced(by: .steps(1))
          } else {
            string?.append(ch)
          }
        case .error:
          if string == nil {
            if grouping == 0 {
              when = when.advanced(by: .steps(1))
            }
            emissions.append((when, .failure(Failure(), index)))
          } else {
            string?.append(ch)
          }
        case .finish:
          if string == nil {
            if grouping == 0 {
              when = when.advanced(by: .steps(1))
            }
            emissions.append((when, .finish(index)))
          } else {
            string?.append(ch)
          }
        case .cancel:
          if string == nil {
            if grouping == 0 {
              when = when.advanced(by: .steps(1))
            }
            emissions.append((when, .cancel(index)))
          } else {
            string?.append(ch)
          }
        case .delayNext:
          if string == nil {
            if grouping == 0 {
              when = when.advanced(by: .steps(1))
            }
            emissions.append((when, .delayNext(index)))
          } else {
            string?.append(ch)
          }
        case .beginValue:
          string = ""
        case .endValue:
          if let value = string {
            string = nil
            if grouping == 0 {
              when = when.advanced(by: .steps(1))
            }
            emissions.append((when, .value(value, index)))
          }
        case .beginGroup:
          guard grouping == 0 else {
            throw ParseFailure.nestedGroup(dsl, index, location)
          }
          when = when.advanced(by: .steps(1))
          grouping += 1
        case .endGroup:
          grouping -= 1
          if grouping < 0 {
            throw ParseFailure.unbalancedNesting(dsl, index, location)
          }
        case .skip:
          string?.append(ch)
          continue
        case .value(let str):
          if string == nil {
            if grouping == 0 {
              when = when.advanced(by: .steps(1))
            }
            emissions.append((when, .value(String(ch), index)))
          } else {
            string?.append(str)
          }
        }
      }
      if grouping != 0 {
        throw ParseFailure.unbalancedNesting(dsl, dsl.endIndex, location)
      }
      return emissions
    }
  }
}

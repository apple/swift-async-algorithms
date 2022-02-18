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

extension MarbleDiagram {
  struct Failure: Error, Equatable { }
  
  enum ParseFailure: Error, CustomStringConvertible {
    case stepInGroup(String, String.Index)
    case nestedGroup(String, String.Index)
    case unbalancedNesting(String, String.Index)
    
    var description: String {
      switch self {
      case .stepInGroup:
        return "marble diagram step symbol in group"
      case .nestedGroup:
        return "marble diagram nested grouping"
      case .unbalancedNesting:
        return "marble diagram unbalanced grouping"
      }
    }
  }
  
  enum Event {
    case value(String, String.Index)
    case failure(Error, String.Index)
    case finish(String.Index)
    case cancel(String.Index)
    
    var results: [Result<String?, Error>] {
      switch self {
      case .value(let value, _): return [.success(value)]
      case .failure(let failure, _): return [.failure(failure)]
      case .finish: return [.success(nil)]
      case .cancel: return []
      }
    }
    
    var index: String.Index {
      switch self {
      case .value(_, let index): return index
      case .failure(_, let index): return index
      case .finish(let index): return index
      case .cancel(let index): return index
      }
    }
    
    static func parse<Theme: MarbleDiagramTheme>(_ dsl: String, theme: Theme) throws -> [(Clock.Instant, Event)] {
      var emissions = [(Clock.Instant, Event)]()
      var when = Clock.Instant(when: .steps(0))
      var string: String?
      var grouping = 0
      
      for index in dsl.indices {
        let ch = dsl[index]
        switch theme.token(dsl[index], inValue: string != nil) {
        case .step:
          if string == nil {
            if grouping == 0 {
              when = when.advanced(by: .steps(1))
            } else {
              throw ParseFailure.stepInGroup(dsl, index)
            }
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
          if grouping == 0 {
            when = when.advanced(by: .steps(1))
          } else {
            throw ParseFailure.nestedGroup(dsl, index)
          }
          grouping += 1
        case .endGroup:
          grouping -= 1
          if grouping < 0 {
            throw ParseFailure.unbalancedNesting(dsl, index)
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
        throw ParseFailure.unbalancedNesting(dsl, dsl.endIndex)
      }
      return emissions
    }
  }
}

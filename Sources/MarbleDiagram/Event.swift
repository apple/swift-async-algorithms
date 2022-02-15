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
  
  enum Event {
    case value(String, String.Index)
    case failure(Error, String.Index)
    case finish(String.Index)
    
    var result: Result<String?, Error> {
      switch self {
      case .value(let value, _): return .success(value)
      case .failure(let failure, _): return .failure(failure)
      case .finish: return .success(nil)
      }
    }
    
    var index: String.Index {
      switch self {
      case .value(_, let index): return index
      case .failure(_, let index): return index
      case .finish(let index): return index
      }
    }
    
    static func parse<Theme: MarbleDiagramTheme>(_ dsl: String, theme: Theme) -> [(ManualClock.Instant, Event)] {
      var emissions = [(ManualClock.Instant, Event)]()
      var when = ManualClock.Instant(0)
      var string: String?
      
      for index in dsl.indices {
        let ch = dsl[index]
        switch theme.token(dsl[index], inValue: string != nil) {
        case .step:
          if string == nil {
            when = when.advanced(by: .steps(1))
          } else {
            string?.append(ch)
          }
        case .error:
          if string == nil {
            when = when.advanced(by: .steps(1))
            emissions.append((when, .failure(Failure(), index)))
          } else {
            string?.append(ch)
          }
        case .finish:
          if string == nil {
            when = when.advanced(by: .steps(1))
            emissions.append((when, .finish(index)))
          } else {
            string?.append(ch)
          }
        case .beginValue:
          string = ""
        case .endValue:
          if let value = string {
            string = nil
            when = when.advanced(by: .steps(1))
            emissions.append((when, .value(value, index)))
          }
        case .skip:
          string?.append(ch)
          continue
        case .value(let str):
          if string == nil {
            when = when.advanced(by: .steps(1))
            emissions.append((when, .value(String(ch), index)))
          } else {
            string?.append(str)
          }
        }
      }
      return emissions
    }
  }
}

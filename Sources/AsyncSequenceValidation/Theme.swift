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

public protocol AsyncSequenceValidationTheme {
  func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token
}

extension AsyncSequenceValidationTheme where Self == AsyncSequenceValidationDiagram.ASCIITheme {
  public static var ascii: AsyncSequenceValidationDiagram.ASCIITheme {
    return AsyncSequenceValidationDiagram.ASCIITheme()
  }
}

extension AsyncSequenceValidationDiagram {
  public enum Token {
    case step
    case error
    case finish
    case cancel
    case beginValue
    case endValue
    case beginGroup
    case endGroup
    case skip
    case value(String)
  }
  
  public struct ASCIITheme: AsyncSequenceValidationTheme {
    public func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token {
      switch character {
      case "-": return .step
      case "^": return .error
      case "|": return .finish
      case ";": return .cancel
      case "'": return inValue ? .endValue : .beginValue
      case "[": return .beginGroup
      case "]": return .endGroup
      case " ": return .skip
      default: return .value(String(character))
      }
    }
  }
}

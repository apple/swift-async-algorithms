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
public protocol AsyncSequenceValidationTheme {
  func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token

  func description(for token: AsyncSequenceValidationDiagram.Token) -> String
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationTheme where Self == AsyncSequenceValidationDiagram.ASCIITheme {
  public static var ascii: AsyncSequenceValidationDiagram.ASCIITheme {
    return AsyncSequenceValidationDiagram.ASCIITheme()
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram {
  public enum Token: Sendable {
    case step
    case error
    case finish
    case cancel
    case delayNext
    case beginValue
    case endValue
    case beginGroup
    case endGroup
    case skip
    case value(String)
  }

  public struct ASCIITheme: AsyncSequenceValidationTheme, Sendable {
    public func token(_ character: Character, inValue: Bool) -> AsyncSequenceValidationDiagram.Token {
      switch character {
      case "-": return .step
      case "^": return .error
      case "|": return .finish
      case ";": return .cancel
      case ",": return .delayNext
      case "'": return inValue ? .endValue : .beginValue
      case "[": return .beginGroup
      case "]": return .endGroup
      case " ": return .skip
      default: return .value(String(character))
      }
    }

    public func description(for token: AsyncSequenceValidationDiagram.Token) -> String {
      switch token {
      case .step: return "-"
      case .error: return "^"
      case .finish: return "|"
      case .cancel: return ";"
      case .delayNext: return ","
      case .beginValue: return "'"
      case .endValue: return "'"
      case .beginGroup: return "["
      case .endGroup: return "]"
      case .skip: return " "
      case .value(let value): return value
      }
    }
  }
}

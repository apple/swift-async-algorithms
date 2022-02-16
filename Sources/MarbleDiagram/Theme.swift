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

public protocol MarbleDiagramTheme {
  func token(_ character: Character, inValue: Bool) -> MarbleDiagram.Token
}

extension MarbleDiagramTheme where Self == MarbleDiagram.ASCIITheme {
  public static var ascii: MarbleDiagram.ASCIITheme {
    return MarbleDiagram.ASCIITheme()
  }
}

extension MarbleDiagram {
  public enum Token {
    case step
    case error
    case finish
    case beginValue
    case endValue
    case beginGroup
    case endGroup
    case skip
    case value(String)
  }
  
  public struct ASCIITheme: MarbleDiagramTheme {
    public func token(_ character: Character, inValue: Bool) -> MarbleDiagram.Token {
      switch character {
      case "-": return .step
      case "^": return .error
      case "|": return .finish
      case "'": return inValue ? .endValue : .beginValue
      case "[": return .beginGroup
      case "]": return .endGroup
      case " ": return .skip
      default: return .value(String(character))
      }
    }
  }
}

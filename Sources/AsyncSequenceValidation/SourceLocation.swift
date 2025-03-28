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

public struct SourceLocation: Sendable, CustomStringConvertible {
  public var file: StaticString
  public var line: UInt

  public init(file: StaticString, line: UInt) {
    self.file = file
    self.line = line
  }

  public var description: String {
    return "\(file):\(line)"
  }
}

public protocol SourceFailure: Error {
  var location: SourceLocation { get }
}

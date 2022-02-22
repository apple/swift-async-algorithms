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

enum PartialIteration<Iterator: AsyncIteratorProtocol, Partial: Sendable>: CustomStringConvertible {
  case idle(Iterator)
  case pending(Task<Partial, Never>)
  case terminal
  
  var description: String {
    switch self {
    case .idle: return "idle"
    case .pending: return "pending"
    case .terminal: return "terminal"
    }
  }
  
  mutating func resolve(_ result: Result<Iterator.Element?, Error>, _ iterator: Iterator) rethrows -> Iterator.Element? {
    do {
      guard let value = try result._rethrowGet() else {
        self = .terminal
        return nil
      }
      self = .idle(iterator)
      return value
    } catch {
      self = .terminal
      throw error
    }
  }
  
  mutating func cancel() {
    if case .pending(let task) = self {
      task.cancel()
    }
    self = .terminal
  }
}

extension PartialIteration: Sendable where Iterator: Sendable, Iterator.Element: Sendable { }

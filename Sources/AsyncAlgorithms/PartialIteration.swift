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

enum PartialIteration<Iterator: AsyncIteratorProtocol & Sendable, Partial: Sendable>: CustomStringConvertible, Sendable where Iterator.Element: Sendable {
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
  
  mutating func task(_ build: @Sendable @escaping (Result<Iterator.Element?, Error>, Iterator) -> Partial) -> Task<Partial, Never>? {
    switch self {
    case .idle(let iterator):
      let task: Task<Partial, Never> = Task {
        var iter = iterator
        do {
          let value = try await iter.next()
          return build(.success(value), iter)
        } catch {
          return build(.failure(error), iter)
        }
      }
      self = .pending(task)
      return task
    case .pending(let task):
      return task
    case .terminal:
      return nil
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

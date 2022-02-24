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

enum Partial2<Iterator1: AsyncIteratorProtocol & Sendable, Iterator2: AsyncIteratorProtocol & Sendable>: Sendable where Iterator1.Element: Sendable, Iterator2.Element: Sendable {
  case first(Result<Iterator1.Element?, Error>, Iterator1)
  case second(Result<Iterator2.Element?, Error>, Iterator2)
  
  init(first iterator: Iterator1) async {
    var iter = iterator
    do {
      let value = try await iter.next()
      self = .first(.success(value), iter)
    } catch {
      self = .first(.failure(error), iter)
    }
  }
  
  init(second iterator: Iterator2) async {
    var iter = iterator
    do {
      let value = try await iter.next()
      self = .second(.success(value), iter)
    } catch {
      self = .second(.failure(error), iter)
    }
  }
}

enum Partial3<Iterator1: AsyncIteratorProtocol & Sendable, Iterator2: AsyncIteratorProtocol & Sendable, Iterator3: AsyncIteratorProtocol & Sendable>: Sendable where Iterator1.Element: Sendable, Iterator2.Element: Sendable, Iterator3.Element: Sendable {
  case first(Result<Iterator1.Element?, Error>, Iterator1)
  case second(Result<Iterator2.Element?, Error>, Iterator2)
  case third(Result<Iterator3.Element?, Error>, Iterator3)

  init(first iterator: Iterator1) async {
    var iter = iterator
    do {
      let value = try await iter.next()
      self = .first(.success(value), iter)
    } catch {
      self = .first(.failure(error), iter)
    }
  }
  
  init(second iterator: Iterator2) async {
    var iter = iterator
    do {
      let value = try await iter.next()
      self = .second(.success(value), iter)
    } catch {
      self = .second(.failure(error), iter)
    }
  }
  
  init(third iterator: Iterator3) async {
    var iter = iterator
    do {
      let value = try await iter.next()
      self = .third(.success(value), iter)
    } catch {
      self = .third(.failure(error), iter)
    }
  }
}

enum PartialIterationState<Iterator: AsyncIteratorProtocol & Sendable, Partial: Sendable>: CustomStringConvertible, Sendable where Iterator.Element: Sendable {
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

extension PartialIterationState {
  mutating func iterate(_ iterator: Iterator) async rethrows -> Iterator.Element? {
    var iter = iterator
    do {
      if let value = try await iter.next() {
        self = .idle(iterator)
        return value
      }
      self = .terminal
      return nil
    } catch {
      self = .terminal
      throw error
    }
  }
  
  mutating func task<Iterator2: AsyncIteratorProtocol & Sendable>() -> Task<Partial, Never>? where Partial == Partial2<Iterator, Iterator2> {
    switch self {
    case .idle(let iterator):
      let task: Task<Partial, Never> = Task {
        await Partial2(first: iterator)
      }
      self = .pending(task)
      return task
    case .pending(let task):
      return task
    case .terminal:
      return nil
    }
  }
  
  mutating func task<Iterator1: AsyncIteratorProtocol & Sendable>() -> Task<Partial, Never>? where Partial == Partial2<Iterator1, Iterator> {
    switch self {
    case .idle(let iterator):
      let task: Task<Partial, Never> = Task {
        await Partial2(second: iterator)
      }
      self = .pending(task)
      return task
    case .pending(let task):
      return task
    case .terminal:
      return nil
    }
  }

  mutating func task<Iterator2: AsyncIteratorProtocol & Sendable, Iterator3: AsyncIteratorProtocol & Sendable>() -> Task<Partial, Never>? where Partial == Partial3<Iterator, Iterator2, Iterator3> {
    switch self {
    case .idle(let iterator):
      let task: Task<Partial, Never> = Task {
        await Partial3(first: iterator)
      }
      self = .pending(task)
      return task
    case .pending(let task):
      return task
    case .terminal:
      return nil
    }
  }
  
  mutating func task<Iterator1: AsyncIteratorProtocol & Sendable, Iterator3: AsyncIteratorProtocol & Sendable>() -> Task<Partial, Never>? where Partial == Partial3<Iterator1, Iterator, Iterator3> {
    switch self {
    case .idle(let iterator):
      let task: Task<Partial, Never> = Task {
        await Partial3(second: iterator)
      }
      self = .pending(task)
      return task
    case .pending(let task):
      return task
    case .terminal:
      return nil
    }
  }
  
  mutating func task<Iterator1: AsyncIteratorProtocol & Sendable, Iterator2: AsyncIteratorProtocol & Sendable>() -> Task<Partial, Never>? where Partial == Partial3<Iterator1, Iterator2, Iterator> {
    switch self {
    case .idle(let iterator):
      let task: Task<Partial, Never> = Task {
        await Partial3(third: iterator)
      }
      self = .pending(task)
      return task
    case .pending(let task):
      return task
    case .terminal:
      return nil
    }
  }
}

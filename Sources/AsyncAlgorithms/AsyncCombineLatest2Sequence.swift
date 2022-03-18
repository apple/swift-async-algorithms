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

/// Creates an asynchronous sequence that combines the latest values from two `AsyncSequence` types
/// by emitting a tuple of the values.
public func combineLatest<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncCombineLatest2Sequence<Base1, Base2> {
  AsyncCombineLatest2Sequence(base1, base2)
}

/// An `AsyncSequence` that combines the latest values produced from two asynchronous sequences into an asynchronous sequence of tuples.
public struct AsyncCombineLatest2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: Sendable
  where
    Base1: Sendable, Base2: Sendable,
    Base1.Element: Sendable, Base2.Element: Sendable,
    Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable {
  let base1: Base1
  let base2: Base2
  
  init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }
}

extension AsyncCombineLatest2Sequence: AsyncSequence {
  public typealias Element = (Base1.Element, Base2.Element)
  
  /// The iterator for a `AsyncCombineLatest2Sequence` instance.
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    enum Partial: Sendable {
      case first(Result<Base1.Element?, Error>, Base1.AsyncIterator)
      case second(Result<Base2.Element?, Error>, Base2.AsyncIterator)
    }
    
    enum State {
      case initial(Base1.AsyncIterator, Base2.AsyncIterator)
      case idle(Base1.AsyncIterator, Base2.AsyncIterator, (Base1.Element, Base2.Element))
      case firstActiveSecondIdle(Task<Partial, Never>, Base2.AsyncIterator, (Base1.Element, Base2.Element))
      case firstIdleSecondActive(Base1.AsyncIterator, Task<Partial, Never>, (Base1.Element, Base2.Element))
      case firstTerminalSecondIdle(Base2.AsyncIterator, (Base1.Element, Base2.Element))
      case firstIdleSecondTerminal(Base1.AsyncIterator, (Base1.Element, Base2.Element))
      case terminal
    }
    
    var state: State
    
    init(_ base1: Base1.AsyncIterator, _ base2: Base2.AsyncIterator) {
      state = .initial(base1, base2)
    }
    
    public mutating func next() async rethrows -> (Base1.Element, Base2.Element)? {
      let task1: Task<Partial, Never>
      let task2: Task<Partial, Never>
      var current: (Base1.Element, Base2.Element)
      
      switch state {
      case .initial(let iterator1, let iterator2):
        func iteration(
          _ group: inout TaskGroup<Partial>,
          _ value1: inout Base1.Element?,
          _ value2: inout Base2.Element?,
          _ iterator1: inout Base1.AsyncIterator?,
          _ iterator2: inout Base2.AsyncIterator?
        ) async -> Result<(Base1.Element, Base2.Element)?, Error>? {
          guard let partial = await group.next() else {
            return .success(nil)
          }
          switch partial {
          case .first(let res, let iter):
            switch res {
            case .success(let value):
              if let value = value {
                value1 = value
                iterator1 = iter
                return nil
              } else {
                group.cancelAll()
                return .success(nil)
              }
            case .failure(let error):
              group.cancelAll()
              return .failure(error)
            }
          case .second(let res, let iter):
            switch res {
            case .success(let value):
              if let value = value {
                value2 = value
                iterator2 = iter
                return nil
              } else {
                group.cancelAll()
                return .success(nil)
              }
            case .failure(let error):
              group.cancelAll()
              return .failure(error)
            }
          }
        }
        
        let (result, iter1, iter2) = await withTaskGroup(of: Partial.self) { group -> (Result<(Base1.Element, Base2.Element)?, Error>, Base1.AsyncIterator?, Base2.AsyncIterator?) in
          group.addTask {
            var iterator = iterator1
            do {
              let value = try await iterator.next()
              return .first(.success(value), iterator)
            } catch {
              return .first(.failure(error), iterator)
            }
          }
          group.addTask {
            var iterator = iterator2
            do {
              let value = try await iterator.next()
              return .second(.success(value), iterator)
            } catch {
              return .second(.failure(error), iterator)
            }
          }
          
          var res1: Base1.Element?
          var res2: Base2.Element?
          var iter1: Base1.AsyncIterator?
          var iter2: Base2.AsyncIterator?
          
          if let result = await iteration(&group, &res1, &res2, &iter1, &iter2) {
            return (result, nil, nil)
          }
          if let result = await iteration(&group, &res1, &res2, &iter1, &iter2) {
            return (result, nil, nil)
          }
          guard let res1 = res1, let res2 = res2 else {
            return (.success(nil), nil, nil)
          }
          
          return (.success((res1, res2)), iter1, iter2)
        }
        do {
          // make sure to get the result first just in case it has a failure embedded
          guard let value = try result._rethrowGet() else {
            state = .terminal
            return nil
          }
          guard let iter1 = iter1, let iter2 = iter2 else {
            state = .terminal
            return nil
          }
          state = .idle(iter1, iter2, value)
          return value
        } catch {
          state = .terminal
          throw error
        }
      case .idle(let iterator1, let iterator2, let value):
        task1 = Task {
          var iterator = iterator1
          do {
            let value = try await iterator.next()
            return .first(.success(value), iterator)
          } catch {
            return .first(.failure(error), iterator)
          }
        }
        task2 = Task {
          var iterator = iterator2
          do {
            let value = try await iterator.next()
            return .second(.success(value), iterator)
          } catch {
            return .second(.failure(error), iterator)
          }
        }
        current = value
      case .firstActiveSecondIdle(let task, let iterator2, let value):
        task1 = task
        task2 = Task {
          var iterator = iterator2
          do {
            let value = try await iterator.next()
            return .second(.success(value), iterator)
          } catch {
            return .second(.failure(error), iterator)
          }
        }
        current = value
      case .firstIdleSecondActive(let iterator1, let task, let value):
        task1 = Task {
          var iterator = iterator1
          do {
            let value = try await iterator.next()
            return .first(.success(value), iterator)
          } catch {
            return .first(.failure(error), iterator)
          }
        }
        task2 = task
        current = value
      case .firstTerminalSecondIdle(var iterator, var current):
        do {
          guard let member = try await iterator.next() else {
            state = .terminal
            return nil
          }
          current.1 = member
          state = .firstTerminalSecondIdle(iterator, current)
          return current
        } catch {
          state = .terminal
          throw error
        }
      case .firstIdleSecondTerminal(var iterator, var current):
        do {
          guard let member = try await iterator.next() else {
            state = .terminal
            return nil
          }
          current.0 = member
          state = .firstIdleSecondTerminal(iterator, current)
          return current
        } catch {
          state = .terminal
          throw error
        }
      case .terminal:
        return nil
      }
      switch await Task.select(task1, task2).value {
      case .first(let result, let iterator):
        switch result {
        case .success(let member):
          if let member = member {
            current.0 = member
            state = .firstIdleSecondActive(iterator, task2, current)
          } else {
            switch await task2.value {
            case .first:
              fatalError()
            case .second(let result, let iterator):
              switch result {
              case .success(let member):
                if let member = member {
                  current.1 = member
                  state = .firstTerminalSecondIdle(iterator, current)
                  return current
                } else {
                  state = .terminal
                  return nil
                }
              case .failure:
                state = .terminal
                try result._rethrowError()
              }
            }
          }
        case .failure:
          state = .terminal
          task2.cancel()
          try result._rethrowError()
        }
      case .second(let result, let iterator):
        switch result {
        case .success(let member):
          if let member = member {
            current.1 = member
            state = .firstActiveSecondIdle(task1, iterator, current)
          } else {
            switch await task1.value {
            case .first(let result, let iterator):
              switch result {
              case .success(let member):
                if let member = member {
                  current.0 = member
                  state = .firstIdleSecondTerminal(iterator, current)
                  return current
                } else {
                  state = .terminal
                  return nil
                }
              case .failure:
                state = .terminal
                try result._rethrowError()
              }
            case .second:
              fatalError()
            }
          }
        case .failure:
          state = .terminal
          task2.cancel()
          try result._rethrowError()
        }
      }
      return current
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator())
  }
}

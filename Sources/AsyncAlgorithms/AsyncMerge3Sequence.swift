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

/// Creates an asynchronous sequence of elements from three underlying asynchronous sequences
public func merge<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(_ base1: Base1, _ base2: Base2, _ base3: Base3) -> AsyncMerge3Sequence<Base1, Base2, Base3>
where
  Base1.Element == Base2.Element,
  Base2.Element == Base3.Element,
  Base1: Sendable, Base2: Sendable, Base3: Sendable,
  Base1.Element: Sendable,
  Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable, Base3.AsyncIterator: Sendable {
  return AsyncMerge3Sequence(base1, base2, base3)
}

/// An asynchronous sequence of elements from three underlying asynchronous sequences
///
/// In a `AsyncMerge3Sequence` instance, the *i*th element is the *i*th element
/// resolved in sequential order out of the two underlying asynchronous sequences.
/// Use the `merge(_:_:_:)` function to create an `AsyncMerge3Sequence`.
public struct AsyncMerge3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: AsyncSequence, Sendable
where
  Base1.Element == Base2.Element,
  Base2.Element == Base3.Element,
  Base1: Sendable, Base2: Sendable, Base3: Sendable,
  Base1.Element: Sendable,
  Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable, Base3.AsyncIterator: Sendable {
  public typealias Element = Base1.Element
  /// An iterator for `AsyncMerge3Sequence`
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    enum Partial: @unchecked Sendable {
      case first(Result<Element?, Error>, Base1.AsyncIterator)
      case second(Result<Element?, Error>, Base2.AsyncIterator)
      case third(Result<Element?, Error>, Base3.AsyncIterator)
    }
    
    var state: (PartialIteration<Base1.AsyncIterator, Partial>, PartialIteration<Base2.AsyncIterator, Partial>, PartialIteration<Base3.AsyncIterator, Partial>)
    
    init(_ iterator1: Base1.AsyncIterator, _ iterator2: Base2.AsyncIterator, _ iterator3: Base3.AsyncIterator) {
      state = (.idle(iterator1), .idle(iterator2), .idle(iterator3))
    }
    
    mutating func apply(_ task1: Task<Partial, Never>?, _ task2: Task<Partial, Never>?, _ task3: Task<Partial, Never>?) async rethrows -> Element? {
      switch await Task.select([task1, task2, task3].compactMap { $0 }).value {
      case .first(let result, let iterator):
        do {
          guard let value = try state.0.resolve(result, iterator) else {
            return try await next()
          }
          return value
        } catch {
          state.1.cancel()
          state.2.cancel()
          throw error
        }
      case .second(let result, let iterator):
        do {
          guard let value = try state.1.resolve(result, iterator) else {
            return try await next()
          }
          return value
        } catch {
          state.0.cancel()
          state.2.cancel()
          throw error
        }
      case .third(let result, let iterator):
        do {
          guard let value = try state.2.resolve(result, iterator) else {
            return try await next()
          }
          return value
        } catch {
          state.0.cancel()
          state.1.cancel()
          throw error
        }
      }
    }
    
    func first(_ iterator1: Base1.AsyncIterator) -> Task<Partial, Never> {
      Task {
        var iter = iterator1
        do {
          let value = try await iter.next()
          return .first(.success(value), iter)
        } catch {
          return .first(.failure(error), iter)
        }
      }
    }
    
    func second(_ iterator2: Base2.AsyncIterator) -> Task<Partial, Never> {
      Task {
        var iter = iterator2
        do {
          let value = try await iter.next()
          return .second(.success(value), iter)
        } catch {
          return .second(.failure(error), iter)
        }
      }
    }
    
    func third(_ iterator3: Base3.AsyncIterator) -> Task<Partial, Never> {
      Task {
        var iter = iterator3
        do {
          let value = try await iter.next()
          return .third(.success(value), iter)
        } catch {
          return .third(.failure(error), iter)
        }
      }
    }
    
    public mutating func next() async rethrows -> Element? {
      // state must have either all terminal or at least 1 idle iterator
      // state may not have a saturation of pending tasks
      switch state {
      // three idle
      case (.idle(let iterator1), .idle(let iterator2), .idle(let iterator3)):
        let task1 = first(iterator1)
        let task2 = second(iterator2)
        let task3 = third(iterator3)
        state = (.pending(task1), .pending(task2), .pending(task3))
        return try await apply(task1, task2, task3)
      // two idle
      case (.idle(let iterator1), .idle(let iterator2), .pending(let task3)):
        let task1 = first(iterator1)
        let task2 = second(iterator2)
        state = (.pending(task1), .pending(task2), .pending(task3))
        return try await apply(task1, task2, task3)
      case (.idle(let iterator1), .pending(let task2), .idle(let iterator3)):
        let task1 = first(iterator1)
        let task3 = third(iterator3)
        state = (.pending(task1), .pending(task2), .pending(task3))
        return try await apply(task1, task2, task3)
      case (.pending(let task1), .idle(let iterator2), .idle(let iterator3)):
        let task2 = second(iterator2)
        let task3 = third(iterator3)
        state = (.pending(task1), .pending(task2), .pending(task3))
        return try await apply(task1, task2, task3)
        
      // 1 idle
      case (.idle(let iterator1), .pending(let task2), .pending(let task3)):
        let task1 = first(iterator1)
        state = (.pending(task1), .pending(task2), .pending(task3))
        return try await apply(task1, task2, task3)
      case (.pending(let task1), .idle(let iterator2), .pending(let task3)):
        let task2 = second(iterator2)
        state = (.pending(task1), .pending(task2), .pending(task3))
        return try await apply(task1, task2, task3)
      case (.pending(let task1), .pending(let task2), .idle(let iterator3)):
        let task3 = third(iterator3)
        state = (.pending(task1), .pending(task2), .pending(task3))
        return try await apply(task1, task2, task3)
        
      // terminal degradations
      // 1 terminal
      case (.terminal, .idle(let iterator2), .idle(let iterator3)):
        let task2 = second(iterator2)
        let task3 = third(iterator3)
        state = (.terminal, .pending(task2), .pending(task3))
        return try await apply(nil, task2, task3)
      case (.terminal, .idle(let iterator2), .pending(let task3)):
        let task2 = second(iterator2)
        state = (.terminal, .pending(task2), .pending(task3))
        return try await apply(nil, task2, task3)
      case (.terminal, .pending(let task2), .idle(let iterator3)):
        let task3 = third(iterator3)
        state = (.terminal, .pending(task2), .pending(task3))
        return try await apply(nil, task2, task3)
      case (.idle(let iterator1), .terminal, .idle(let iterator3)):
        let task1 = first(iterator1)
        let task3 = third(iterator3)
        state = (.pending(task1), .terminal, .pending(task3))
        return try await apply(task1, nil, task3)
      case (.idle(let iterator1), .terminal, .pending(let task3)):
        let task1 = first(iterator1)
        state = (.pending(task1), .terminal, .pending(task3))
        return try await apply(task1, nil, task3)
      case (.pending(let task1), .terminal, .idle(let iterator3)):
        let task3 = third(iterator3)
        state = (.pending(task1), .terminal, .pending(task3))
        return try await apply(task1, nil, task3)
      case (.idle(let iterator1), .idle(let iterator2), .terminal):
        let task1 = first(iterator1)
        let task2 = second(iterator2)
        state = (.pending(task1), .pending(task2), .terminal)
        return try await apply(task1, task2, nil)
      case (.idle(let iterator1), .pending(let task2), .terminal):
        let task1 = first(iterator1)
        state = (.pending(task1), .pending(task2), .terminal)
        return try await apply(task1, task2, nil)
      case (.pending(let task1), .idle(let iterator2), .terminal):
        let task2 = second(iterator2)
        state = (.pending(task1), .pending(task2), .terminal)
        return try await apply(task1, task2, nil)
        
      // 2 terminal
      // these can be permuted in place since they don't need to run two or more tasks at once
      case (.terminal, .terminal, .idle(var iterator3)):
        do {
          if let value = try await iterator3.next() {
            state = (.terminal, .terminal, .idle(iterator3))
            return value
          } else {
            state = (.terminal, .terminal, .terminal)
            return nil
          }
        } catch {
          state = (.terminal, .terminal, .terminal)
          throw error
        }
      case (.terminal, .idle(var iterator2), .terminal):
        do {
          if let value = try await iterator2.next() {
            state = (.terminal, .idle(iterator2), .terminal)
            return value
          } else {
            state = (.terminal, .terminal, .terminal)
            return nil
          }
        } catch {
          state = (.terminal, .terminal, .terminal)
          throw error
        }
      case (.idle(var iterator1), .terminal, .terminal):
        do {
          if let value = try await iterator1.next() {
            state = (.idle(iterator1), .terminal, .terminal)
            return value
          } else {
            state = (.terminal, .terminal, .terminal)
            return nil
          }
        } catch {
          state = (.terminal, .terminal, .terminal)
          throw error
        }
      // 3 terminal
      case (.terminal, .terminal, .terminal):
        return nil
      // partials
      case (.pending(let task1), .pending(let task2), .pending(let task3)):
        return try await apply(task1, task2, task3)
      case (.pending(let task1), .pending(let task2), .terminal):
        return try await apply(task1, task2, nil)
      case (.pending(let task1), .terminal, .pending(let task3)):
        return try await apply(task1, nil, task3)
      case (.terminal, .pending(let task2), .pending(let task3)):
        return try await apply(nil, task2, task3)
      case (.pending(let task1), .terminal, .terminal):
        return try await apply(task1, nil, nil)
      case (.terminal, .pending(let task2), .terminal):
        return try await apply(nil, task2, nil)
      case (.terminal, .terminal, .pending(let task3)):
        return try await apply(nil, nil, task3)
      }
    }
  }
    
  let base1: Base1
  let base2: Base2
  let base3: Base3

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }

  public func makeAsyncIterator() -> Iterator {
    return Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator(), base3.makeAsyncIterator())
  }
}

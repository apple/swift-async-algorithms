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

/// Creates an asynchronous sequence of elements from two underlying asynchronous sequences
public func merge<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncMerge2Sequence<Base1, Base2>
where
  Base1.Element == Base2.Element,
  Base1: Sendable, Base2: Sendable,
  Base1.Element: Sendable,
  Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable {
  return AsyncMerge2Sequence(base1, base2)
}

/// An asynchronous sequence of elements from two underlying asynchronous sequences
///
/// In a `AsyncMerge2Sequence` instance, the *i*th element is the *i*th element
/// resolved in sequential order out of the two underyling asynchronous sequences.
/// Use the `merge(_:_:)` function to create an `AsyncMerge2Sequence`.
public struct AsyncMerge2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: AsyncSequence, Sendable
where
  Base1.Element == Base2.Element,
  Base1: Sendable, Base2: Sendable,
  Base1.Element: Sendable,
  Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable {
  public typealias Element = Base1.Element
  /// An iterator for `AsyncMerge2Sequence`
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    enum Partial: @unchecked Sendable {
      case first(Result<Element?, Error>, Base1.AsyncIterator)
      case second(Result<Element?, Error>, Base2.AsyncIterator)
    }
    
    var state: (PartialIteration<Base1.AsyncIterator, Partial>, PartialIteration<Base2.AsyncIterator, Partial>)
    
    init(_ iterator1: Base1.AsyncIterator, _ iterator2: Base2.AsyncIterator) {
      state = (.idle(iterator1), .idle(iterator2))
    }
    
    mutating func apply(_ task1: Task<Partial, Never>?, _ task2: Task<Partial, Never>?) async rethrows -> Element? {
      switch await Task.select([task1, task2].compactMap { $0 }).value {
      case .first(let result, let iterator):
        do {
          guard let value = try state.0.resolve(result, iterator) else {
            return try await next()
          }
          return value
        } catch {
          state.1.cancel()
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
    
    /// Advances to the next element and returns it or `nil` if no next element exists.
    public mutating func next() async rethrows -> Element? {
      if Task.isCancelled {
        state.0.cancel()
        state.1.cancel()
        return nil
      }
      switch state {
      case (.idle(let iterator1), .idle(let iterator2)):
        return try await apply(first(iterator1), second(iterator2))
      case (.idle(let iterator1), .pending(let task2)):
        return try await apply(first(iterator1), task2)
      case (.pending(let task1), .idle(let iterator2)):
        return try await apply(task1, second(iterator2))
      case (.idle(var iterator1), .terminal):
        do {
          if let value = try await iterator1.next() {
            state = (.idle(iterator1), .terminal)
            return value
          } else {
            state = (.terminal, .terminal)
            return nil
          }
        } catch {
          state = (.terminal, .terminal)
          throw error
        }
      case (.terminal, .idle(var iterator2)):
        do {
          if let value = try await iterator2.next() {
            state = (.terminal, .idle(iterator2))
            return value
          } else {
            state = (.terminal, .terminal)
            return nil
          }
        } catch {
          state = (.terminal, .terminal)
          throw error
        }
      case (.terminal, .terminal):
        return nil
      default:
        fatalError()
      }
    }
  }
  
  let base1: Base1
  let base2: Base2
  
  init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }
  
  public func makeAsyncIterator() -> Iterator {
    return Iterator(base1.makeAsyncIterator(), base2.makeAsyncIterator())
  }
}

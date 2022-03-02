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

extension AsyncSequence where Self: Sendable, Element: AsyncSequence & Sendable, AsyncIterator: Sendable, Element.AsyncIterator: Sendable, Element.Element: Sendable {
  public func switchToLatest() -> AsyncSwitchToLatestSequence<Self> {
    return AsyncSwitchToLatestSequence(self)
  }
}

public struct AsyncSwitchToLatestSequence<Base: AsyncSequence>: Sendable where Base.Element: AsyncSequence, Base.Element: Sendable, Base.AsyncIterator: Sendable, Base.Element.AsyncIterator: Sendable, Base.Element.Element: Sendable, Base: Sendable {
  let base: Base
  
  init(_ base: Base) {
    self.base = base
  }
}

extension AsyncSwitchToLatestSequence: AsyncSequence {
  public typealias Element = Base.Element.Element
  
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    enum Partial {
      case base(Result<Base.Element?, Error>, Base.AsyncIterator)
      case active(Result<Base.Element.Element?, Error>, Base.Element.AsyncIterator)
    }
    
    enum Latest {
      case initial
      case idle(Base.Element.AsyncIterator)
      case pending(Task<Partial, Never>)
      case terminal
      
      mutating func cancel() {
        switch self {
        case .pending(let task):
          self = .terminal
          task.cancel()
        default:
          self = .terminal
        }
      }
    }
    
    var state: (PartialIteration<Base.AsyncIterator, Partial>, Latest)
    
    init(_ iterator: Base.AsyncIterator) {
      state = (.idle(iterator), .initial)
    }
    
    public mutating func next() async rethrows -> Element? {
      if Task.isCancelled {
        state.0.cancel()
        state.1.cancel()
        return nil
      }
      var base: Task<Partial, Never>?
      var active: Task<Partial, Never>?
      switch state {
      case (.idle(var baseIterator), .initial):
        do {
          guard let activeSeq = try await baseIterator.next() else {
            state.0 = .terminal
            state.1 = .terminal
            return nil
          }
          let activeIterator = activeSeq.makeAsyncIterator()
          base = Task { [baseIterator] in
            var iterator = baseIterator
            do {
              let value = try await iterator.next()
              return .base(.success(value), iterator)
            } catch {
              return .base(.failure(error), iterator)
            }
          }
          active = Task { [activeIterator] in
            var iterator = activeIterator
            do {
              let value = try await iterator.next()
              return .active(.success(value), iterator)
            } catch {
              return .active(.failure(error), iterator)
            }
          }
        } catch {
          state.0 = .terminal
          state.1 = .terminal
          throw error
        }
        break
      case (.pending(let baseTask), .initial):
        switch await baseTask.value {
        case .base(let result, let baseIterator):
          do {
            guard let activeSeq = try result._rethrowGet() else {
              state.0 = .terminal
              state.1 = .terminal
              return nil
            }
            let activeIterator = activeSeq.makeAsyncIterator()
            base = Task { [baseIterator] in
              var iterator = baseIterator
              do {
                let value = try await iterator.next()
                return .base(.success(value), iterator)
              } catch {
                return .base(.failure(error), iterator)
              }
            }
            active = Task { [activeIterator] in
              var iterator = activeIterator
              do {
                let value = try await iterator.next()
                return .active(.success(value), iterator)
              } catch {
                return .active(.failure(error), iterator)
              }
            }
          } catch {
            state.0 = .terminal
            state.1 = .terminal
            throw error
          }
        case .active:
          fatalError()
        }
        break
      case (.terminal, .initial):
        return nil
      case (.idle(let baseIterator), .idle(let activeIterator)):
        base = Task { [baseIterator] in
          var iterator = baseIterator
          do {
            let value = try await iterator.next()
            return .base(.success(value), iterator)
          } catch {
            return .base(.failure(error), iterator)
          }
        }
        active = Task { [activeIterator] in
          var iterator = activeIterator
          do {
            let value = try await iterator.next()
            return .active(.success(value), iterator)
          } catch {
            return .active(.failure(error), iterator)
          }
        }
      case (.pending(let baseTask), .idle(let activeIterator)):
        base = baseTask
        active = Task { [activeIterator] in
          var iterator = activeIterator
          do {
            let value = try await iterator.next()
            return .active(.success(value), iterator)
          } catch {
            return .active(.failure(error), iterator)
          }
        }
      case (.terminal, .idle(var activeIterator)):
        do {
          guard let value = try await activeIterator.next() else {
            state.1 = .terminal
            return nil
          }
          state.1 = .idle(activeIterator)
          return value
        } catch {
          state.1 = .terminal
          throw error
        }
      case (.idle(let baseIterator), .pending(let activeTask)):
        base = Task { [baseIterator] in
          var iterator = baseIterator
          do {
            let value = try await iterator.next()
            return .base(.success(value), iterator)
          } catch {
            return .base(.failure(error), iterator)
          }
        }
        active = activeTask
      case (.pending(let baseTask), .pending(let activeTask)):
        base = baseTask
        active = activeTask
      case (.terminal, .pending(let activeTask)):
        switch await activeTask.value {
        case .base:
          fatalError()
        case .active(let result, let iterator):
          do {
            guard let value = try result._rethrowGet() else {
              state.1 = .terminal
              return nil
            }
            state.1 = .idle(iterator)
            return value
          } catch {
            state.1 = .terminal
            throw error
          }
        }
        break
      case (.idle(var baseIterator), .terminal):
        do {
          guard let activeSeq = try await baseIterator.next() else {
            state.0 = .terminal
            return nil
          }
          let activeIterator = activeSeq.makeAsyncIterator()
          base = Task { [baseIterator] in
            var iterator = baseIterator
            do {
              let value = try await iterator.next()
              return .base(.success(value), iterator)
            } catch {
              return .base(.failure(error), iterator)
            }
          }
          active = Task { [activeIterator] in
            var iterator = activeIterator
            do {
              let value = try await iterator.next()
              return .active(.success(value), iterator)
            } catch {
              return .active(.failure(error), iterator)
            }
          }
        } catch {
          state.0 = .terminal
        }
        break
      case (.pending(let baseTask), .terminal):
        switch await baseTask.value {
        case .base(let result, let baseIterator):
          do {
            guard let activeSeq = try result._rethrowGet() else {
              state.0 = .terminal
              state.1 = .terminal
              return nil
            }
            let activeIterator = activeSeq.makeAsyncIterator()
            base = Task { [baseIterator] in
              var iterator = baseIterator
              do {
                let value = try await iterator.next()
                return .base(.success(value), iterator)
              } catch {
                return .base(.failure(error), iterator)
              }
            }
            active = Task { [activeIterator] in
              var iterator = activeIterator
              do {
                let value = try await iterator.next()
                return .active(.success(value), iterator)
              } catch {
                return .active(.failure(error), iterator)
              }
            }
          } catch {
            state.0 = .terminal
            state.1 = .terminal
            throw error
          }
        case .active:
          fatalError()
        }
      case (.terminal, .terminal):
        return nil
      }
      state = (.pending(base!), .pending(active!))
      switch await Task.select(base!, active!).value {
      case .base(let result, let baseIterator):
        switch result {
        case .success(let activeSeq):
          if let activeSeq = activeSeq {
            let activeIterator = activeSeq.makeAsyncIterator()
            state = (.idle(baseIterator), .idle(activeIterator))
            return try await next()
          } else {
            state.0 = .terminal
            return try await next()
          }
        case .failure:
          state.0 = .terminal
          state.1 = .terminal
          active!.cancel()
          try result._rethrowError()
        }
      case .active(let result, let activeIterator):
        switch result {
        case .success(let value):
          if let value = value {
            state.1 = .idle(activeIterator)
            return value
          } else {
            state.1 = .terminal
            return try await next()
          }
        case .failure:
          state.0 = .terminal
          state.1 = .terminal
          base!.cancel()
          try result._rethrowError()
        }
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator())
  }
}


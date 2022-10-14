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

import DequeModule

extension AsyncSequence where Self: Sendable, Element: Sendable {
  public func broadcast() -> AsyncBroadcastSequence<Self> {
    AsyncBroadcastSequence(self)
  }
}

public struct AsyncBroadcastSequence<Base: AsyncSequence>: Sendable where Base: Sendable, Base.Element: Sendable {
  struct State : Sendable {
    enum Terminal {
      case failure(Error)
      case finished
    }
    
    struct Side {
      var buffer = Deque<Element>()
      var terminal: Terminal?
      var continuation: UnsafeContinuation<Result<Element?, Error>, Never>?
      
      mutating func drain() {
        if !buffer.isEmpty, let continuation {
          let element = buffer.removeFirst()
          continuation.resume(returning: .success(element))
          self.continuation = nil
        } else if let terminal, let continuation {
          switch terminal {
          case .failure(let error):
            self.terminal = .finished
            continuation.resume(returning: .failure(error))
          case .finished:
            continuation.resume(returning: .success(nil))
          }
          self.continuation = nil
        }
      }
      
      mutating func cancel() {
        buffer.removeAll()
        terminal = .finished
        drain()
      }
      
      mutating func next(_ continuation: UnsafeContinuation<Result<Element?, Error>, Never>) {
        assert(self.continuation == nil) // presume that the sides are NOT sendable iterators...
        self.continuation = continuation
        drain()
      }
      
      mutating func emit(_ result: Result<Element?, Error>) {
        switch result {
        case .success(let element):
          if let element {
            buffer.append(element)
          } else {
            terminal = .finished
          }
        case .failure(let error):
          terminal = .failure(error)
        }
        drain()
      }
    }
    
    var id = 0
    var sides = [Int: Side]()
    
    init() { }
    
    mutating func establish() -> Int {
      defer { id += 1 }
      sides[id] = Side()
      return id
    }
    
    static func establish(_ state: ManagedCriticalState<State>) -> Int {
      state.withCriticalRegion { $0.establish() }
    }
    
    mutating func cancel(_ id: Int) {
      if var side = sides.removeValue(forKey: id) {
        side.cancel()
      }
    }
    
    static func cancel(_ state: ManagedCriticalState<State>, id: Int) {
      state.withCriticalRegion { $0.cancel(id) }
    }
    
    mutating func next(_ id: Int, continuation: UnsafeContinuation<Result<Element?, Error>, Never>) {
      sides[id]?.next(continuation)
    }
    
    static func next(_ state: ManagedCriticalState<State>, id: Int) async -> Result<Element?, Error> {
      await withUnsafeContinuation { continuation in
        state.withCriticalRegion { $0.next(id, continuation: continuation) }
      }
    }
    
    mutating func emit(_ result: Result<Element?, Error>) {
      for id in sides.keys {
        sides[id]?.emit(result)
      }
    }
    
    static func emit(_ state: ManagedCriticalState<State>, result: Result<Element?, Error>) {
      state.withCriticalRegion { $0.emit(result) }
    }
  }
  
  struct Iteration {
    enum Status {
      case initial(Base)
      case iterating(Task<Void, Never>)
      case terminal
    }
    
    var status: Status
    
    init(_ base: Base) {
      status = .initial(base)
    }
    
    static func task(_ state: ManagedCriticalState<State>, base: Base) -> Task<Void, Never> {
      Task {
        do {
          for try await element in base {
            State.emit(state, result: .success(element))
          }
          State.emit(state, result: .success(nil))
        } catch {
          State.emit(state, result: .failure(error))
        }
      }
    }
    
    mutating func start(_ state: ManagedCriticalState<State>) -> Bool {
      switch status {
      case .terminal:
        return false
      case .initial(let base):
        status = .iterating(Iteration.task(state, base: base))
      default:
        break
      }
      return true
    }
    
    mutating func cancel() {
      switch status {
      case .iterating(let task):
        task.cancel()
      default:
        break
      }
      status = .terminal
    }
    
    static func start(_ iteration: ManagedCriticalState<Iteration>, state: ManagedCriticalState<State>) -> Bool {
      iteration.withCriticalRegion { $0.start(state) }
    }
    
    static func cancel(_ iteration: ManagedCriticalState<Iteration>) {
      iteration.withCriticalRegion { $0.cancel() }
    }
  }
  
  let state: ManagedCriticalState<State>
  let iteration: ManagedCriticalState<Iteration>
  
  init(_ base: Base) {
    state = ManagedCriticalState(State())
    iteration = ManagedCriticalState(Iteration(base))
  }
}


extension AsyncBroadcastSequence: AsyncSequence {
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol {
    final class Context {
      let state: ManagedCriticalState<State>
      var iteration: ManagedCriticalState<Iteration>
      let id: Int
      
      init(_ state: ManagedCriticalState<State>, _ iteration: ManagedCriticalState<Iteration>) {
        self.state = state
        self.iteration = iteration
        self.id = State.establish(state)
      }
      
      deinit {
        State.cancel(state, id: id)
        if iteration.isKnownUniquelyReferenced() {
          Iteration.cancel(iteration)
        }
      }
      
      func next() async rethrows -> Element? {
        guard Iteration.start(iteration, state: state) else {
          return nil
        }
        defer {
          if Task.isCancelled && iteration.isKnownUniquelyReferenced() {
            Iteration.cancel(iteration)
          }
        }
        return try await withTaskCancellationHandler {
          let result = await State.next(state, id: id)
          return try result._rethrowGet()
        } onCancel: { [state, id] in
          State.cancel(state, id: id)
        }
      }
    }
    
    let context: Context
    
    init(_ state: ManagedCriticalState<State>, _ iteration: ManagedCriticalState<Iteration>) {
      context = Context(state, iteration)
    }
    
    public mutating func next() async rethrows -> Element? {
      try await context.next()
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(state, iteration)
  }
}

@available(*, unavailable)
extension AsyncBroadcastSequence.Iterator: Sendable { }

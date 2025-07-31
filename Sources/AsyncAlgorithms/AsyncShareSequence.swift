import Synchronization

@available(macOS 26.0, *)
extension AsyncSequence where Element: Sendable {
  @available(macOS 26.0, *) // TODO: fix the availability for this to be defined as @available(AsyncAlgorithms 1.1, *)
  public func share(bufferingPolicy: AsyncBufferSequencePolicy = .unbounded) -> some AsyncSequence<Element, Failure> & Sendable {
    return AsyncShareSequence(self, bufferingPolicy: bufferingPolicy)
  }
}

@available(macOS 26.0, *)
struct AsyncShareSequence<Base: AsyncSequence>: Sendable where Base.Element: Sendable {
  final class Side {
    struct State {
      var continuaton: CheckedContinuation<Result<Element?, Failure>, Never>?
      var position = 0
      
      func offset(_ adjustment: Int) -> State {
        State(continuaton: continuaton, position: position - adjustment)
      }
    }
    
    let iteration: Iteration
    let id: Int
    
    init(_ iteration: Iteration) {
      self.iteration = iteration
      id = iteration.registerSide()
    }
    
    deinit {
      iteration.unregisterSide(id)
    }
    
    func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
      try await iteration.next(isolation: actor, id: id)
    }
  }
  
  final class Iteration: Sendable {
    // this is the swapped state of transferring the base to the iterating task
    // it does send the Base... but only one transfer
    enum IteratingTask: @unchecked Sendable {
      case pending(Base)
      case starting
      case running(Task<Void, Never>)
      case cancelled
      
      var isStarting: Bool {
        switch self {
        case .starting: true
        default: false
        }
      }
      
      func cancel() {
        switch self {
        case .running(let task):
          task.cancel()
        default:
          break
        }
      }
    }
    struct State: Sendable {
      enum StoragePolicy: Sendable {
        case unbounded
        case bufferingOldest(Int)
        case bufferingNewest(Int)
      }
      
      var generation = 0
      var sides = [Int: Side.State]()
      var iteratingTask: IteratingTask
      var buffer = [Element]()
      var finished = false
      var failure: Failure?
      var cancelled = false
      var limit: CheckedContinuation<Bool, Never>?
      var demand: CheckedContinuation<Void, Never>?
      
      let storagePolicy: StoragePolicy
      
      init(_ base: Base, bufferingPolicy: AsyncBufferSequencePolicy) {
        self.iteratingTask = .pending(base)
        switch bufferingPolicy.policy {
        case .bounded: self.storagePolicy = .unbounded
        case .bufferingOldest(let bound): self.storagePolicy = .bufferingOldest(bound)
        case .bufferingNewest(let bound): self.storagePolicy = .bufferingNewest(bound)
        case .unbounded: self.storagePolicy = .unbounded
        }
      }
      
      mutating func trimBuffer() {
        if let minimumIndex = sides.values.map({ $0.position }).min(), minimumIndex > 0 {
          buffer.removeFirst(minimumIndex)
          sides = sides.mapValues {
            $0.offset(minimumIndex)
          }
        }
      }
      
      mutating func emit<T>(_ value: T) -> (T, CheckedContinuation<Bool, Never>?, CheckedContinuation<Void, Never>?, Bool) {
        defer {
          limit = nil
          demand = nil
        }
        if case .cancelled = iteratingTask {
          return (value, limit, demand, true)
        } else {
          return (value, limit, demand, false)
        }
      }
      
      mutating func enqueue(_ element: Element) {
        let count = buffer.count
        
        switch storagePolicy {
        case .unbounded:
          buffer.append(element)
        case .bufferingOldest(let limit):
          if count < limit {
            buffer.append(element)
          }
        case .bufferingNewest(let limit):
          if count < limit {
            buffer.append(element)
          } else if count > 0 {
            buffer.removeFirst()
            buffer.append(element)
          }
        }
      }
      
      mutating func finish() {
        finished = true
      }
      
      mutating func fail(_ error: Failure) {
        finished = true
        failure = error
      }
    }
    
    let state: Mutex<State>
    let limit: Int?
    
    init(_ base: Base, bufferingPolicy: AsyncBufferSequencePolicy) {
      state = Mutex(State(base, bufferingPolicy: bufferingPolicy))
      switch bufferingPolicy.policy {
      case .bounded(let limit):
        self.limit = limit
      default:
        self.limit = nil
      }
    }
    
    func cancel() {
      let (task, limit, demand, cancelled) = state.withLock { state -> (IteratingTask?, CheckedContinuation<Bool, Never>?, CheckedContinuation<Void, Never>?, Bool)  in
        if state.sides.count == 0 {
          defer {
            state.iteratingTask = .cancelled
            state.cancelled = true
          }
          return state.emit(state.iteratingTask)
        } else {
          state.cancelled = true
          return state.emit(nil)
        }
      }
      task?.cancel()
      limit?.resume(returning: cancelled)
      demand?.resume()
    }
    
    func registerSide() -> Int {
      state.withLock { state in
        defer { state.generation += 1 }
        state.sides[state.generation] = Side.State()
        return state.generation
      }
    }
    
    func unregisterSide(_ id: Int) {
      let (side, continuation, cancelled, iteratingTaskToCancel) = state.withLock { state -> (Side.State?, CheckedContinuation<Bool, Never>?, Bool, IteratingTask?) in
        let side = state.sides.removeValue(forKey: id)
        state.trimBuffer()
        let cancelRequested = state.sides.count == 0 && state.cancelled
        if let limit, state.buffer.count < limit {
          defer { state.limit = nil }
          if case .cancelled = state.iteratingTask {
            return (side, state.limit, true, nil)
          } else {
            defer {
              if cancelRequested {
                state.iteratingTask = .cancelled
              }
            }
            return (side, state.limit, false, cancelRequested ? state.iteratingTask : nil)
          }
        } else {
          if case .cancelled = state.iteratingTask {
            return (side, nil, true, nil)
          } else {
            defer {
              if cancelRequested {
                state.iteratingTask = .cancelled
              }
            }
            return (side, nil, false, cancelRequested ? state.iteratingTask : nil)
          }
        }
      }
      if let continuation {
        continuation.resume(returning: cancelled)
      }
      if let side {
        side.continuaton?.resume(returning: .success(nil))
      }
      if let iteratingTaskToCancel {
        iteratingTaskToCancel.cancel()
      }
    }
    
    func iterate() async -> Bool {
      if let limit {
        let cancelled = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
          let (resume, cancelled) = state.withLock { state -> (CheckedContinuation<Bool, Never>?, Bool) in
            if state.buffer.count >= limit {
              state.limit = continuation
              if case .cancelled = state.iteratingTask {
                return (nil, true)
              } else {
                return (nil, false)
              }
            } else {
              assert(state.limit == nil)
              if case .cancelled = state.iteratingTask {
                return (continuation, true)
              } else {
                return (continuation, false)
              }
            }
          }
          if let resume {
            resume.resume(returning: cancelled)
          }
        }
        if cancelled {
          return false
        }
      }
      
      // await a demand
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let hasPendingDemand = state.withLock { state in
          for (_, side) in state.sides {
            if side.continuaton != nil {
              return true
            }
          }
          state.demand = continuation
          return false
        }
        if hasPendingDemand {
          continuation.resume()
        }
      }
      return state.withLock { state in
        switch state.iteratingTask {
        case .cancelled:
          return false
        default:
          return true
        }
      }
    }
    
    func cancel(id: Int) {
      unregisterSide(id) // doubly unregistering is idempotent but has a side effect of emitting nil if present
    }
    
    struct Resumption {
      let continuation: CheckedContinuation<Result<Element?, Failure>, Never>
      let result: Result<Element?, Failure>
      
      func resume() {
        continuation.resume(returning: result)
      }
    }
    
    func emit(_ result: Result<Element?, Failure>) {
      let (resumptions, demandContinuation) = state.withLock { state -> ([Resumption], CheckedContinuation<Void, Never>?) in
        var resumptions = [Resumption]()
        switch result {
        case .success(let element):
          if let element {
            state.enqueue(element)
          } else {
            state.finished = true
          }
        case .failure(let failure):
          state.finished = true
          state.failure = failure
        }
        for (id, side) in state.sides {
          if let continuation = side.continuaton {
            if side.position < state.buffer.count {
              resumptions.append(Resumption(continuation: continuation, result: .success(state.buffer[side.position])))
              state.sides[id]?.position += 1
              state.sides[id]?.continuaton = nil
            } else if state.finished {
              state.sides[id]?.continuaton = nil
              if let failure = state.failure {
                resumptions.append(Resumption(continuation: continuation, result: .failure(failure)))
              } else {
                resumptions.append(Resumption(continuation: continuation, result: .success(nil)))
              }
            }
          }
        }
        state.trimBuffer()
        if let limit, state.buffer.count < limit {
          defer {
            state.demand = nil
          }
          return (resumptions, state.demand)
        } else {
          return (resumptions, nil)
        }
      }
      if let demandContinuation {
        demandContinuation.resume()
      }
      for resumption in resumptions {
        resumption.resume()
      }
    }
    
    func next(isolation actor: isolated (any Actor)?, id: Int) async throws(Failure) -> Element? {
      let (base, cancelled) = state.withLock { state -> (Base?, Bool) in
        switch state.iteratingTask {
        case .pending(let base):
          state.iteratingTask = .starting
          return (base, false)
        case .cancelled:
          return (nil, true)
        default:
          return (nil, false)
        }
      }
      if cancelled { return nil }
      if let base {
        nonisolated(unsafe) let transfer = base.makeAsyncIterator()
        let task = Task.detached { [transfer, self] in
          var iterator = transfer
          do {
            while await iterate() {
              if let element = try await iterator.next() {
                emit(.success(element))
              } else {
                emit(.success(nil))
              }
            }
          } catch {
            emit(.failure(error as! Failure))
          }
        }
        state.withLock { state in
          precondition(state.iteratingTask.isStarting)
          state.iteratingTask = .running(task)
        }
      }
      let result: Result<Element?, Failure> = await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          let (res, limitContinuation, demandContinuation, cancelled) = state.withLock { state -> (Result<Element?, Failure>?, CheckedContinuation<Bool, Never>?, CheckedContinuation<Void, Never>?, Bool) in
            let side = state.sides[id]!
            if side.position < state.buffer.count {
              // There's an element available at this position
              let element = state.buffer[side.position]
              state.sides[id]?.position += 1
              state.trimBuffer()
              return state.emit(.success(element))
            } else {
              // Position is beyond the buffer
              if let failure = state.failure {
                return state.emit(.failure(failure))
              } else if state.finished {
                return state.emit(.success(nil))
              } else {
                state.sides[id]?.continuaton = continuation
                return state.emit(nil)
              }
            }
          }
          if let limitContinuation {
            limitContinuation.resume(returning: cancelled)
          }
          if let demandContinuation {
            demandContinuation.resume()
          }
          if let res {
            continuation.resume(returning: res)
          }
        }
      } onCancel: {
        cancel(id: id)
      }
      
      return try result.get()
    }
  }
  
  final class Extent: Sendable {
    let iteration: Iteration
    
    init(_ base: Base, bufferingPolicy: AsyncBufferSequencePolicy) {
      iteration = Iteration(base, bufferingPolicy: bufferingPolicy)
    }
    
    deinit {
      iteration.cancel()
    }
  }
  
  let extent: Extent
  
  init(_ base: Base, bufferingPolicy: AsyncBufferSequencePolicy) {
    extent = Extent(base, bufferingPolicy: bufferingPolicy)
  }
}

@available(macOS 26.0, *)
extension AsyncShareSequence: AsyncSequence {
  typealias Element = Base.Element
  typealias Failure = Base.Failure
  
  struct Iterator: AsyncIteratorProtocol {
    
    
    let side: Side
    
    init(_ iteration: Iteration) {
      side = Side(iteration)
    }
    
    mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
      try await side.next(isolation: actor)
    }
  }
  
  func makeAsyncIterator() -> Iterator {
    Iterator(extent.iteration)
  }
}

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

import Synchronization

@available(AsyncAlgorithms 1.1, *)
extension AsyncSequence where Element: Sendable, Self: SendableMetatype, AsyncIterator: SendableMetatype {
  /// Creates a shared async sequence that allows multiple concurrent iterations over a single source.
  ///
  /// The `share` method transforms an async sequence into a shareable sequence that can be safely
  /// iterated by multiple concurrent tasks. This is useful when you want to broadcast elements from
  /// a single source to multiple consumers without duplicating work or creating separate iterations.
  ///
  /// - Important: Each element from the source sequence is delivered to all active iterators.
  ///   Elements are buffered according to the specified buffering policy to handle timing differences
  ///   between consumers.
  ///
  /// - Parameter bufferingPolicy: The policy controlling how elements are buffered when consumers
  ///   iterate at different rates. Defaults to `.bounded(1)`.
  ///   - `.bounded(n)`: Limits the buffer to `n` elements, applying backpressure to the source when that limit is reached
  ///   - `.bufferingOldest(n)`: Keeps the oldest `n` elements, discarding newer ones when full
  ///   - `.bufferingNewest(n)`: Keeps the newest `n` elements, discarding older ones when full  
  ///   - `.unbounded`: Allows unlimited buffering (use with caution)
  ///
  /// - Returns: A sendable async sequence that can be safely shared across multiple concurrent tasks.
  ///
  /// ## Example Usage
  ///
  /// ```swift
  /// let numbers = AsyncStream<Int> { continuation in
  ///     Task {
  ///         for i in 1...5 {
  ///             continuation.yield(i)
  ///             try await Task.sleep(for: .seconds(1))
  ///         }
  ///         continuation.finish()
  ///     }
  /// }
  ///
  /// let shared = numbers.share()
  ///
  /// // Multiple tasks can iterate concurrently
  /// async let consumer1 = Task {
  ///     for await value in shared {
  ///         print("Consumer 1: \(value)")
  ///     }
  /// }
  ///
  /// async let consumer2 = Task {
  ///     for await value in shared {
  ///         print("Consumer 2: \(value)")
  ///     }
  /// }
  ///
  /// await consumer1.value
  /// await consumer2.value
  /// ```
  ///
  /// ## Buffering Behavior
  ///
  /// The buffering policy determines how the shared sequence handles elements when consumers
  /// iterate at different speeds:
  ///
  /// - **Bounded**: Applies backpressure to slow down the source when the buffer is full
  /// - **Buffering Oldest**: Drops new elements when the buffer is full, preserving older ones
  /// - **Buffering Newest**: Drops old elements when the buffer is full, preserving newer ones
  /// - **Unbounded**: Never drops elements but may consume unbounded memory
  ///
  /// - Note: The source async sequence's iterator is consumed only once, regardless of how many
  ///   concurrent consumers are active. This makes sharing efficient for expensive-to-produce sequences.
  public func share(bufferingPolicy: AsyncBufferSequencePolicy = .bounded(1)) -> some AsyncSequence<Element, Failure> & Sendable {
    // the iterator is transferred to the isolation of the iterating task
    // this has to be done "unsafely" since we cannot annotate the transfer
    // however since iterating an AsyncSequence types twice has been defined
    // as invalid and one creation of the iterator is virtually a consuming
    // operation so this is safe at runtime.
    nonisolated(unsafe) let iterator = makeAsyncIterator()
    return AsyncShareSequence<Self>( {
      iterator
    }, bufferingPolicy: bufferingPolicy)
  }
}

// An async sequence that enables safe concurrent sharing of a single source sequence.
//
// `AsyncShareSequence` wraps a base async sequence and allows multiple concurrent iterators
// to consume elements from the same source. It handles all the complexity of coordinating
// between multiple consumers, buffering elements, and managing the lifecycle of the underlying
// iteration.
//
// ## Key Features
//
// - **Single Source Iteration**: The base sequence's iterator is created and consumed only once
// - **Concurrent Safe**: Multiple tasks can safely iterate simultaneously
// - **Configurable Buffering**: Supports various buffering strategies for different use cases
// - **Automatic Cleanup**: Properly manages resources and cancellation across all consumers
//
// ## Internal Architecture
//
// The implementation uses several key components:
// - `Side`: Represents a single consumer's iteration state
// - `Iteration`: Coordinates all consumers and manages the shared buffer
// - `Extent`: Manages the overall lifecycle and cleanup
//
// This type is typically not used directly; instead, use the `share()` method on any
// async sequence that meets the sendability requirements.
@available(AsyncAlgorithms 1.1, *)
struct AsyncShareSequence<Base: AsyncSequence>: Sendable where Base.Element: Sendable, Base: SendableMetatype, Base.AsyncIterator: SendableMetatype {
  // Represents a single consumer's connection to the shared sequence.
  //
  // Each iterator of the shared sequence creates its own `Side` instance, which tracks
  // that consumer's position in the shared buffer and manages its continuation for
  // async iteration. The `Side` automatically registers itself with the central
  // `Iteration` coordinator and cleans up when deallocated.
  //
  // ## Lifecycle
  //
  // - **Creation**: Automatically registers with the iteration coordinator
  // - **Usage**: Tracks buffer position and manages async continuations
  // - **Cleanup**: Automatically unregisters and cancels pending operations on deinit
  final class Side {
    // Tracks the state of a single consumer's iteration.
    //
    // - `continuaton`: The continuation waiting for the next element (nil if not waiting)
    // - `position`: The consumer's current position in the shared buffer
    struct State {
      var continuaton: UnsafeContinuation<Result<Element?, Failure>, Never>?
      var position = 0
      
      // Creates a new state with the position adjusted by the given offset.
      //
      // This is used when the shared buffer is trimmed to maintain correct
      // relative positioning for this consumer.
      //
      // - Parameter adjustment: The number of positions to subtract from the current position
      // - Returns: A new `State` with the adjusted position
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
  
  // The central coordinator that manages the shared iteration state.
  //
  // `Iteration` is responsible for:
  // - Managing the single background task that consumes the source sequence
  // - Coordinating between multiple consumer sides
  // - Buffering elements according to the specified policy
  // - Handling backpressure and flow control
  // - Managing cancellation and cleanup
  //
  // ## Thread Safety
  //
  // All operations are synchronized using a `Mutex` to ensure thread-safe access
  // to the shared state across multiple concurrent consumers.
  final class Iteration: Sendable {
    // Represents the state of the background task that consumes the source sequence.
    //
    // The iteration task goes through several states during its lifecycle:
    // - `pending`: Initial state, holds the factory to create the iterator
    // - `starting`: Transitional state while the task is being created
    // - `running`: Active state with a running background task
    // - `cancelled`: Terminal state when the iteration has been cancelled
    enum IteratingTask {
      case pending(@Sendable () -> sending Base.AsyncIterator)
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
    // The complete shared state for coordinating all aspects of the shared iteration.
    //
    // This state is protected by a mutex and contains all the information needed
    // to coordinate between multiple consumers, manage buffering, and control
    // the background iteration task.
    struct State: Sendable {
      // Defines how elements are stored and potentially discarded in the shared buffer.
      //
      // - `unbounded`: Store all elements without limit (may cause memory growth)
      // - `bufferingOldest(Int)`: Keep only the oldest N elements, ignore newer ones when full
      // - `bufferingNewest(Int)`: Keep only the newest N elements, discard older ones when full
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
      var limit: UnsafeContinuation<Bool, Never>?
      var demand: UnsafeContinuation<Void, Never>?
      
      let storagePolicy: StoragePolicy
      
      init(_ iteratorFactory: @escaping @Sendable () -> sending Base.AsyncIterator, bufferingPolicy: AsyncBufferSequencePolicy) {
        self.iteratingTask = .pending(iteratorFactory)
        switch bufferingPolicy.policy {
        case .bounded: self.storagePolicy = .unbounded
        case .bufferingOldest(let bound): self.storagePolicy = .bufferingOldest(bound)
        case .bufferingNewest(let bound): self.storagePolicy = .bufferingNewest(bound)
        case .unbounded: self.storagePolicy = .unbounded
        }
      }
      
      // Removes elements from the front of the buffer that all consumers have already processed.
      //
      // This method finds the minimum position across all active consumers and removes
      // that many elements from the front of the buffer. It then adjusts all consumer
      // positions to account for the removed elements, maintaining their relative positions.
      //
      // This optimization prevents the buffer from growing indefinitely when all consumers
      // are keeping pace with each other.
      mutating func trimBuffer() {
        if let minimumIndex = sides.values.map({ $0.position }).min(), minimumIndex > 0 {
          buffer.removeFirst(minimumIndex)
          sides = sides.mapValues {
            $0.offset(minimumIndex)
          }
        }
      }
      
      // Private state machine transitions for the emission of a given value.
      //
      // This method ensures the continuations are properly consumed when emitting values
      // and returns those continuations for resumption.
      private mutating func _emit<T>(_ value: T, limit: Int) -> (T, UnsafeContinuation<Bool, Never>?, UnsafeContinuation<Void, Never>?, Bool) {
        let belowLimit = buffer.count < limit || limit == 0
        defer {
          if belowLimit {
            self.limit = nil
          }
          demand = nil
        }
        if case .cancelled = iteratingTask {
          return (value, belowLimit ? self.limit : nil, demand, true)
        } else {
          return (value, belowLimit ? self.limit : nil, demand, false)
        }
      }
      
      // Internal state machine transitions for the emission of a given value.
      //
      // This method ensures the continuations are properly consumed when emitting values
      // and returns those continuations for resumption.
      //
      // If no limit is specified it interprets that as an unbounded limit.
      mutating func emit<T>(_ value: T, limit: Int?) -> (T, UnsafeContinuation<Bool, Never>?, UnsafeContinuation<Void, Never>?, Bool) {
        return _emit(value, limit: limit ?? .max)
      }
      
      // Adds an element to the buffer according to the configured storage policy.
      //
      // The behavior depends on the storage policy:
      // - **Unbounded**: Always appends the element
      // - **Buffering Oldest**: Appends only if under the limit, otherwise ignores the element
      // - **Buffering Newest**: Appends if under the limit, otherwise removes the oldest and appends
      //
      // - Parameter element: The element to add to the buffer
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
    
    init(_ iteratorFactory: @escaping @Sendable () -> sending Base.AsyncIterator, bufferingPolicy: AsyncBufferSequencePolicy) {
      state = Mutex(State(iteratorFactory, bufferingPolicy: bufferingPolicy))
      switch bufferingPolicy.policy {
      case .bounded(let limit):
        self.limit = limit
      default:
        self.limit = nil
      }
    }
    
    func cancel() {
      let (task, limitContinuation, demand, cancelled) = state.withLock { state -> (IteratingTask?, UnsafeContinuation<Bool, Never>?, UnsafeContinuation<Void, Never>?, Bool)  in
        if state.sides.count == 0 {
          defer {
            state.iteratingTask = .cancelled
            state.cancelled = true
          }
          return state.emit(state.iteratingTask, limit: limit)
        } else {
          state.cancelled = true
          return state.emit(nil, limit: limit)
        }
      }
      task?.cancel()
      limitContinuation?.resume(returning: cancelled)
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
      let (side, continuation, cancelled, iteratingTaskToCancel) = state.withLock { state -> (Side.State?, UnsafeContinuation<Bool, Never>?, Bool, IteratingTask?) in
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
        let cancelled = await withUnsafeContinuation { (continuation: UnsafeContinuation<Bool, Never>) in
          let (resume, cancelled) = state.withLock { state -> (UnsafeContinuation<Bool, Never>?, Bool) in
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
      await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
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
      let continuation: UnsafeContinuation<Result<Element?, Failure>, Never>
      let result: Result<Element?, Failure>
      
      func resume() {
        continuation.resume(returning: result)
      }
    }
    
    func emit(_ result: Result<Element?, Failure>) {
      let (resumptions, limitContinuation, demandContinuation, cancelled) = state.withLock { state -> ([Resumption], UnsafeContinuation<Bool, Never>?, UnsafeContinuation<Void, Never>?, Bool) in
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
        return state.emit(resumptions, limit: limit)
      }
      
      if let limitContinuation {
        limitContinuation.resume(returning: cancelled)
      }
      if let demandContinuation {
        demandContinuation.resume()
      }
      for resumption in resumptions {
        resumption.resume()
      }
    }
    
    func next(isolation actor: isolated (any Actor)?, id: Int) async throws(Failure) -> Element? {
      let (factory, cancelled) = state.withLock { state -> ((@Sendable () -> sending Base.AsyncIterator)?, Bool) in
        switch state.iteratingTask {
        case .pending(let factory):
          state.iteratingTask = .starting
          return (factory, false)
        case .cancelled:
          return (nil, true)
        default:
          return (nil, false)
        }
      }
      if cancelled { return nil }
      if let factory {
        // this has to be interfaced as detached since we want the priority inference
        // from the creator to not have a direct effect on the iteration.
        // This might be improved later by passing on the creation context's task
        // priority.
        let task = Task.detached(name: "Share Iteration") { [factory, self] in
          var iterator = factory()
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
        await withUnsafeContinuation { continuation in
          let (res, limitContinuation, demandContinuation, cancelled) = state.withLock { state -> (Result<Element?, Failure>?, UnsafeContinuation<Bool, Never>?, UnsafeContinuation<Void, Never>?, Bool) in
            guard let side = state.sides[id] else {
              return state.emit(.success(nil), limit: limit)
            }
            if side.position < state.buffer.count {
              // There's an element available at this position
              let element = state.buffer[side.position]
              state.sides[id]?.position += 1
              state.trimBuffer()
              return state.emit(.success(element), limit: limit)
            } else {
              // Position is beyond the buffer
              if let failure = state.failure {
                return state.emit(.failure(failure), limit: limit)
              } else if state.finished {
                return state.emit(.success(nil), limit: limit)
              } else {
                state.sides[id]?.continuaton = continuation
                return state.emit(nil, limit: limit)
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
  
  // Manages the lifecycle of the shared iteration.
  //
  // `Extent` serves as the ownership boundary for the shared sequence. When the
  // `AsyncShareSequence` itself is deallocated, the `Extent` ensures that the
  // background iteration task is properly cancelled and all resources are cleaned up.
  //
  // This design allows multiple iterators to safely reference the same underlying
  // iteration coordinator while ensuring proper cleanup when the shared sequence
  // is no longer needed.
  final class Extent: Sendable {
    let iteration: Iteration
    
    init(_ iteratorFactory: @escaping @Sendable () -> sending Base.AsyncIterator, bufferingPolicy: AsyncBufferSequencePolicy) {
      iteration = Iteration(iteratorFactory, bufferingPolicy: bufferingPolicy)
    }
    
    deinit {
      iteration.cancel()
    }
  }
  
  let extent: Extent
  
  
  init(_ iteratorFactory: @escaping @Sendable () -> sending Base.AsyncIterator, bufferingPolicy: AsyncBufferSequencePolicy) {
    extent = Extent(iteratorFactory, bufferingPolicy: bufferingPolicy)
  }
}

@available(AsyncAlgorithms 1.1, *)
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

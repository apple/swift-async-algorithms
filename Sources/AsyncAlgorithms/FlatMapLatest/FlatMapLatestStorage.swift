//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@available(AsyncAlgorithms 1.1, *)
final class FlatMapLatestStorage<Base: AsyncSequence & Sendable, Inner: AsyncSequence & Sendable>: @unchecked Sendable where Base.Element: Sendable, Inner.Element: Sendable {
  typealias Element = Inner.Element
  
  private let lock = Lock.allocate()
  private var stateMachine: FlatMapLatestStateMachine<Base, Inner>
  
  init(base: Base, transform: @escaping @Sendable (Base.Element) -> Inner) {
    self.stateMachine = FlatMapLatestStateMachine(base: base, transform: transform)
  }
  
  deinit {
    lock.deinitialize()
  }
  
  func next(isolation: isolated (any Actor)? = #isolation) async throws(Inner.Failure) -> Inner.Element? {
    do {
      return try await withTaskCancellationHandler {
        lock.lock()
        let action = stateMachine.next()
        
        switch action {
        case .returnElement(let element):
          lock.unlock()
          return element
          
        case .returnNil:
          lock.unlock()
          return nil
          
        case .throwError(let error):
          lock.unlock()
          throw error
          
        case .startOuterTask(let base):
          // We need to start the outer task and then suspend
          startOuterTask(base)
          
          return try await suspend()
          
        case .suspend:
          lock.unlock()
          return try await suspend()
        }
      } onCancel: {
        let action = lock.withLock { stateMachine.cancelled() }
        handleAction(action)
      }
    } catch {
      throw error as! Inner.Failure
    }
  }
  
  private func suspend() async throws -> Element? {
    return try await withUnsafeThrowingContinuation { continuation in
      let action = lock.withLock { stateMachine.next(for: continuation) }
      
      switch action {
      case .resumeOuterContinuation(let continuation):
        continuation.resume()
      case .resumeInnerContinuation(let continuation):
        continuation.resume()
      case .none:
        break
      }
    }
  }
  
  private func startOuterTask(_ base: Base) {
    let task = Task {
      var iterator = base.makeAsyncIterator()
      
      loop: while true {
        // Create a continuation to wait for demand
        do {
          try await withUnsafeThrowingContinuation { continuation in
            let action = lock.withLock { stateMachine.outerTaskSuspended(continuation) }
            
            switch action {
            case .resumeOuterContinuation(let continuation):
              continuation.resume()
            case .resumeInnerContinuation(let continuation):
              continuation.resume()
            case .none:
              break
            }
          }
        } catch {
          // Cancellation or other error during suspension
          let action = lock.withLock { stateMachine.outerThrew(error) }
          handleAction(action)
          break loop
        }
        
        do {
          if let element = try await iterator.next() {
            let action = lock.withLock { stateMachine.outerElementProduced(element) }
            handleAction(action)
          } else {
            let action = lock.withLock { stateMachine.outerFinished() }
            handleAction(action)
            break loop
          }
        } catch {
          let action = lock.withLock { stateMachine.outerThrew(error) }
          handleAction(action)
          break loop
        }
      }
    }
    stateMachine.outerTaskStarted(task)
    lock.unlock()
  }
  
  private func startInnerTask(_ inner: Inner, generation: Int) {
    let task = Task {
      var iterator = inner.makeAsyncIterator()
      
      loop: while true {
        // Wait for demand
        do {
          try await withUnsafeThrowingContinuation { continuation in
            let action = lock.withLock { stateMachine.innerTaskSuspended(continuation, generation: generation) }
            
            switch action {
            case .resumeInnerContinuation(let continuation):
              continuation.resume()
            case .resumeOuterContinuation(let continuation):
              continuation.resume()
            case .none:
              break
            }
          }
        } catch {
           // Cancellation
           let action = lock.withLock { stateMachine.innerThrew(error, generation: generation) }
           handleAction(action)
           break loop
        }
        
        do {
          if let element = try await iterator.next() {
            let action = lock.withLock { stateMachine.innerElementProduced(element, generation: generation) }
            handleAction(action)
          } else {
            let action = lock.withLock { stateMachine.innerFinished(generation: generation) }
            handleAction(action)
            break loop
          }
        } catch {
          let action = lock.withLock { stateMachine.innerThrew(error, generation: generation) }
          handleAction(action)
          break loop
        }
      }
    }
    stateMachine.innerTaskStarted(task, generation: generation)
  }
  
  private func handleAction(_ action: FlatMapLatestStateMachine<Base, Inner>.Action) {
    switch action {
    case .startInnerTask(let inner, let generation, let previousTask, let previousCont):
      if let previousTask = previousTask {
        previousTask.cancel()
        previousCont?.resume(throwing: CancellationError())
      }
      startInnerTask(inner, generation: generation)
      
    case .cancelInnerTask(let task, let continuation):
      task.cancel()
      continuation?.resume(throwing: CancellationError())
      
    case .resumeDownstream(let continuation, let result):
      continuation.resume(with: result)
      
    case .resumeOuterContinuation(let continuation):
      continuation.resume()
      
    case .cancelTasks(let outer, let inner, let outerCont, let innerCont):
      outer?.cancel()
      inner?.cancel()
      outerCont?.resume(throwing: CancellationError())
      innerCont?.resume(throwing: CancellationError())
      
    case .none:
      break
    }
  }
}

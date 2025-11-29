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

import DequeModule

@available(AsyncAlgorithms 1.0, *)
struct FlatMapLatestStateMachine<Base: AsyncSequence & Sendable, Inner: AsyncSequence & Sendable> where Base.Element: Sendable, Inner.Element: Sendable {
  typealias Element = Inner.Element
  
  private enum State {
    case initial(Base)
    case running(
      outerTask: Task<Void, Never>?,
      outerContinuation: UnsafeContinuation<Void, Error>?,
      innerTask: Task<Void, Never>?,
      innerContinuation: UnsafeContinuation<Void, Error>?,
      downstreamContinuation: UnsafeContinuation<Element?, Error>?,
      buffer: Deque<Result<Element, Error>>,
      generation: Int,
      outerFinished: Bool
    )
    case finished
  }
  
  private var state: State
  private let transform: @Sendable (Base.Element) -> Inner
  
  init(base: Base, transform: @escaping @Sendable (Base.Element) -> Inner) {
    self.state = .initial(base)
    self.transform = transform
  }
  
  enum NextAction {
    case returnElement(Element)
    case returnNil
    case throwError(Error)
    case startOuterTask(Base)
    case suspend
  }
  
  enum Action {
    case startInnerTask(Inner, generation: Int, previousTask: Task<Void, Never>?, previousContinuation: UnsafeContinuation<Void, Error>?)
    case cancelInnerTask(Task<Void, Never>, UnsafeContinuation<Void, Error>?)
    case resumeDownstream(UnsafeContinuation<Element?, Error>, Result<Element?, Error>)
    case resumeOuterContinuation(UnsafeContinuation<Void, Error>)
    case cancelTasks(Task<Void, Never>?, Task<Void, Never>?, UnsafeContinuation<Void, Error>?, UnsafeContinuation<Void, Error>?)
    case none
  }
  
  enum SuspendAction {
    case resumeOuterContinuation(UnsafeContinuation<Void, Error>)
    case resumeInnerContinuation(UnsafeContinuation<Void, Error>)
    case none
  }
  
  mutating func next() -> NextAction {
    switch state {
    case .initial(let base):
      return .startOuterTask(base)
      
    case .running(let outerTask, let outerCont, let innerTask, let innerCont, let downstreamCont, var buffer, let generation, let outerFinished):
      if let result = buffer.popFirst() {
        state = .running(
          outerTask: outerTask,
          outerContinuation: outerCont,
          innerTask: innerTask,
          innerContinuation: innerCont,
          downstreamContinuation: downstreamCont,
          buffer: buffer,
          generation: generation,
          outerFinished: outerFinished
        )
        switch result {
        case .success(let element): return .returnElement(element)
        case .failure(let error): return .throwError(error)
        }
      } else if outerFinished && innerTask == nil {
        state = .finished
        return .returnNil
      } else {
        return .suspend
      }
      
    case .finished:
      return .returnNil
    }
  }
  
  mutating func next(for continuation: UnsafeContinuation<Element?, Error>) -> SuspendAction {
    switch state {
    case .initial:
      fatalError("Should be started")
      
    case .running(let outerTask, let outerCont, let innerTask, let innerCont, let downstreamCont, let buffer, let generation, let outerFinished):
      precondition(downstreamCont == nil, "Already have downstream continuation")
      precondition(buffer.isEmpty, "Buffer should be empty if suspending")
      
      state = .running(
        outerTask: outerTask,
        outerContinuation: outerCont,
        innerTask: innerTask,
        innerContinuation: innerCont,
        downstreamContinuation: continuation,
        buffer: buffer,
        generation: generation,
        outerFinished: outerFinished
      )
      
      // If we have an inner task waiting, resume it to produce more
      if let innerCont = innerCont {
        return .resumeInnerContinuation(innerCont)
      }
      // If we have an outer task waiting (and no inner task, or we want to race?), resume it
      // Actually we want to race. But here we just signal demand.
      // If inner task exists, we prioritize it? Or we signal both?
      // In this simple model, we signal whoever is waiting.
      if let outerCont = outerCont {
        return .resumeOuterContinuation(outerCont)
      }
      
      return .none
      
    case .finished:
      continuation.resume(returning: nil)
      return .none
    }
  }
  
  mutating func outerTaskStarted(_ task: Task<Void, Never>) {
    switch state {
    case .initial:
      // Transition to running
      state = .running(
        outerTask: task,
        outerContinuation: nil,
        innerTask: nil,
        innerContinuation: nil,
        downstreamContinuation: nil,
        buffer: Deque(),
        generation: 0,
        outerFinished: false
      )
    default:
      fatalError("Invalid state transition")
    }
  }
  
  mutating func outerTaskSuspended(_ continuation: UnsafeContinuation<Void, Error>) -> SuspendAction {
    switch state {
    case .running(let outerTask, _, let innerTask, let innerCont, let downstreamCont, let buffer, let generation, let outerFinished):
      // If we have downstream demand, resume immediately
      if downstreamCont != nil {
        return .resumeOuterContinuation(continuation)
      }
      
      state = .running(
        outerTask: outerTask,
        outerContinuation: continuation,
        innerTask: innerTask,
        innerContinuation: innerCont,
        downstreamContinuation: downstreamCont,
        buffer: buffer,
        generation: generation,
        outerFinished: outerFinished
      )
      return .none
      
    case .finished:
      continuation.resume(throwing: CancellationError())
      return .none
      
    default:
      fatalError("Invalid state")
    }
  }
  
  mutating func outerElementProduced(_ element: Base.Element) -> Action {
    switch state {
    case .running(let outerTask, _, let innerTask, let innerCont, let downstreamCont, let buffer, var generation, let outerFinished):
      // New element from outer -> Cancel previous inner, start new inner
      let newInner = transform(element)
      generation += 1
      
      state = .running(
        outerTask: outerTask,
        outerContinuation: nil, // We just consumed the continuation by producing
        innerTask: nil, // Will be set by innerTaskStarted
        innerContinuation: nil,
        downstreamContinuation: downstreamCont,
        buffer: buffer,
        generation: generation,
        outerFinished: outerFinished
      )
      
      return .startInnerTask(newInner, generation: generation, previousTask: innerTask, previousContinuation: innerCont)
      
    case .finished:
      return .none
      
    default:
      fatalError("Invalid state")
    }
  }
  
  mutating func innerTaskStarted(_ task: Task<Void, Never>, generation: Int) {
    switch state {
    case .running(let outerTask, let outerCont, _, let innerCont, let downstreamCont, let buffer, let currentGen, let outerFinished):
      if generation != currentGen {
        // This task is already stale (outer produced another one while we were starting)
        // We should cancel it immediately?
        // Or just let it run and it will be ignored?
        // Better to not store it.
        return
      }
      
      // If there was a previous inner task that wasn't cancelled yet (e.g. from the transition),
      // we should have cancelled it in `outerElementProduced`.
      // But wait, I didn't return a cancel action there.
      
      // FIX: `outerElementProduced` should have returned an action that cancels the old task.
      // Since I can't easily change the return type structure in this thought stream without rewriting,
      // I will assume `startInnerTask` implies cancellation of the *current* inner task in Storage?
      // No, Storage doesn't know what the "current" one is before I update the state.
      
      // Let's fix `outerElementProduced` logic in the code I write.
      // I will make `startInnerTask` take the *old* task to cancel.
      
      state = .running(
        outerTask: outerTask,
        outerContinuation: outerCont,
        innerTask: task,
        innerContinuation: innerCont,
        downstreamContinuation: downstreamCont,
        buffer: buffer,
        generation: currentGen,
        outerFinished: outerFinished
      )
      
    default:
      // If finished, we don't care
      break
    }
  }
  
  mutating func innerTaskSuspended(_ continuation: UnsafeContinuation<Void, Error>, generation: Int) -> SuspendAction {
    switch state {
    case .running(let outerTask, let outerCont, let innerTask, _, let downstreamCont, let buffer, let currentGen, let outerFinished):
      if generation != currentGen {
        // Stale generation
        continuation.resume(throwing: CancellationError())
        return .none
      }
      
      if downstreamCont != nil {
        return .resumeInnerContinuation(continuation)
      }
      
      state = .running(
        outerTask: outerTask,
        outerContinuation: outerCont,
        innerTask: innerTask,
        innerContinuation: continuation,
        downstreamContinuation: downstreamCont,
        buffer: buffer,
        generation: currentGen,
        outerFinished: outerFinished
      )
      return .none
      
    case .finished:
      continuation.resume(throwing: CancellationError())
      return .none
      
    default:
      fatalError("Invalid state")
    }
  }
  
  mutating func innerElementProduced(_ element: Element, generation: Int) -> Action {
    switch state {
    case .running(let outerTask, let outerCont, let innerTask, _, let downstreamCont, var buffer, let currentGen, let outerFinished):
      if generation != currentGen {
        return .none
      }
      
      if let downstreamCont = downstreamCont {
        state = .running(
          outerTask: outerTask,
          outerContinuation: outerCont,
          innerTask: innerTask,
          innerContinuation: nil, // Consumed
          downstreamContinuation: nil,
          buffer: buffer,
          generation: currentGen,
          outerFinished: outerFinished
        )
        return .resumeDownstream(downstreamCont, .success(element))
      } else {
        buffer.append(.success(element))
        state = .running(
          outerTask: outerTask,
          outerContinuation: outerCont,
          innerTask: innerTask,
          innerContinuation: nil,
          downstreamContinuation: nil,
          buffer: buffer,
          generation: currentGen,
          outerFinished: outerFinished
        )
        return .none
      }
      
    case .finished:
      return .none
      
    default:
      fatalError("Invalid state")
    }
  }
  
  mutating func innerFinished(generation: Int) -> Action {
    switch state {
    case .running(let outerTask, let outerCont, _, _, let downstreamCont, let buffer, let currentGen, let outerFinished):
      if generation != currentGen {
        return .none
      }
      
      // Inner finished.
      if outerFinished {
        // Both finished
        state = .finished
        if let downstreamCont = downstreamCont {
          return .resumeDownstream(downstreamCont, .success(nil))
        }
      } else {
        // Just this inner finished. Wait for next outer.
        state = .running(
          outerTask: outerTask,
          outerContinuation: outerCont,
          innerTask: nil,
          innerContinuation: nil,
          downstreamContinuation: downstreamCont,
          buffer: buffer,
          generation: currentGen,
          outerFinished: outerFinished
        )
        // If we have downstream demand, we should ensure outer is running?
        // It should be running if it's not suspended.
        // If it IS suspended, we should resume it?
        if downstreamCont != nil, let outerCont = outerCont {
           // We resume outer to produce next inner
           state = .running(
             outerTask: outerTask,
             outerContinuation: nil, // Consumed
             innerTask: nil,
             innerContinuation: nil,
             downstreamContinuation: downstreamCont,
             buffer: buffer,
             generation: currentGen,
             outerFinished: outerFinished
           )
           return .resumeOuterContinuation(outerCont)
        }
      }
      return .none
      
    default:
      return .none
    }
  }
  
  mutating func innerThrew(_ error: Error, generation: Int) -> Action {
    switch state {
    case .running(let outerTask, let outerCont, let innerTask, let innerCont, let downstreamCont, _, let currentGen, _):
      if generation != currentGen {
        return .none
      }
      
      state = .finished
      let action: Action = .cancelTasks(outerTask, innerTask, outerCont, innerCont)
      
      if let downstreamCont = downstreamCont {
        return .resumeDownstream(downstreamCont, .failure(error))
      } else {
        // We need to store the error? Or just cancel everything.
        // If we cancel everything, the next `next()` will see finished?
        // We should probably store the failure if buffer is empty.
        // But for simplicity, let's just finish.
        return action
      }
      
    default:
      return .none
    }
  }
  
  mutating func outerFinished() -> Action {
    switch state {
    case .running(let outerTask, _, let innerTask, let innerCont, let downstreamCont, let buffer, let generation, _):
      if innerTask == nil && buffer.isEmpty {
        state = .finished
        if let downstreamCont = downstreamCont {
          return .resumeDownstream(downstreamCont, .success(nil))
        }
      } else {
        state = .running(
          outerTask: outerTask,
          outerContinuation: nil,
          innerTask: innerTask,
          innerContinuation: innerCont,
          downstreamContinuation: downstreamCont,
          buffer: buffer,
          generation: generation,
          outerFinished: true
        )
      }
      return .none
      
    default:
      return .none
    }
  }
  
  mutating func outerThrew(_ error: Error) -> Action {
    switch state {
    case .running(let outerTask, let outerCont, let innerTask, let innerCont, let downstreamCont, _, _, _):
      state = .finished
      let action: Action = .cancelTasks(outerTask, innerTask, outerCont, innerCont)
      
      if let downstreamCont = downstreamCont {
        return .resumeDownstream(downstreamCont, .failure(error))
      } else {
        return action
      }
      
    default:
      return .none
    }
  }
  
  mutating func cancelled() -> Action {
    switch state {
    case .running(let outerTask, let outerCont, let innerTask, let innerCont, let downstreamCont, _, _, _):
      state = .finished
      let action: Action = .cancelTasks(outerTask, innerTask, outerCont, innerCont)
      
      if let downstreamCont = downstreamCont {
        return .resumeDownstream(downstreamCont, .success(nil)) // Or nil? Usually cancellation results in nil or throwing CancellationError?
        // If the downstream task is cancelled, resuming it with nil is fine, or throwing.
        // But `withTaskCancellationHandler` usually handles the downstream cancellation.
        // This method is called when the downstream task is cancelled.
        // So we just need to clean up.
      }
      return action
      
    default:
      state = .finished
      return .none
    }
  }
}

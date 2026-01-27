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

@available(AsyncAlgorithms 1.1, *)
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
      
      // Resume waiting tasks to produce elements for downstream demand
      if let innerCont = innerCont {
        return .resumeInnerContinuation(innerCont)
      }
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
        // Stale task from previous generation, ignore it
        return
      }
      
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
        // Resume outer sequence if downstream is waiting for more elements
        if downstreamCont != nil, let outerCont = outerCont {
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
        return .resumeDownstream(downstreamCont, .success(nil))
      }
      return action
      
    default:
      state = .finished
      return .none
    }
  }
}

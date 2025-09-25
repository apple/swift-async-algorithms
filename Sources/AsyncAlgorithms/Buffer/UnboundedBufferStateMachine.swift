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

@available(AsyncAlgorithms 1.0, *)
struct UnboundedBufferStateMachine<Base: AsyncSequence> {
  typealias Element = Base.Element
  typealias SuspendedConsumer = UnsafeContinuation<UnsafeTransfer<Result<Element, Error>?>, Never>

  enum Policy {
    case unlimited
    case bufferingNewest(Int)
    case bufferingOldest(Int)
  }

  // We are using UnsafeTransfer here since we have to get the elements from the task
  // into the consumer task. This is a transfer but we cannot prove this to the compiler at this point
  // since next is not marked as transferring the return value.
  fileprivate enum State {
    case initial(base: Base)
    case buffering(
      task: Task<Void, Never>,
      buffer: Deque<Result<UnsafeTransfer<Element>, Error>>,
      suspendedConsumer: SuspendedConsumer?
    )
    case modifying
    case finished(buffer: Deque<Result<UnsafeTransfer<Element>, Error>>)
  }

  private var state: State
  private let policy: Policy

  init(base: Base, policy: Policy) {
    self.state = .initial(base: base)
    self.policy = policy
  }

  var task: Task<Void, Never>? {
    switch self.state {
    case .buffering(let task, _, _):
      return task
    default:
      return nil
    }
  }

  mutating func taskStarted(task: Task<Void, Never>) {
    switch self.state {
    case .initial:
      self.state = .buffering(task: task, buffer: [], suspendedConsumer: nil)

    case .buffering:
      preconditionFailure("Invalid state.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      preconditionFailure("Invalid state.")
    }
  }

  enum ElementProducedAction {
    case none
    case resumeConsumer(
      continuation: SuspendedConsumer,
      result: UnsafeTransfer<Result<Element, Error>?>
    )
  }

  mutating func elementProduced(element: Element) -> ElementProducedAction {
    switch self.state {
    case .initial:
      preconditionFailure("Invalid state. The task should already by started.")

    case .buffering(let task, var buffer, .none):
      // we are either idle or the buffer is already in use (no awaiting consumer)
      // we have to apply the policy when stacking the new element
      self.state = .modifying
      switch self.policy {
      case .unlimited:
        buffer.append(.success(.init(element)))
      case .bufferingNewest(let limit):
        if buffer.count >= limit {
          _ = buffer.popFirst()
        }
        buffer.append(.success(.init(element)))
      case .bufferingOldest(let limit):
        if buffer.count < limit {
          buffer.append(.success(.init(element)))
        }
      }
      self.state = .buffering(task: task, buffer: buffer, suspendedConsumer: nil)
      return .none

    case .buffering(let task, let buffer, .some(let suspendedConsumer)):
      // we have an awaiting consumer, we can resume it with the element
      precondition(buffer.isEmpty, "Invalid state. The buffer should be empty.")
      self.state = .buffering(task: task, buffer: buffer, suspendedConsumer: nil)
      return .resumeConsumer(
        continuation: suspendedConsumer,
        result: UnsafeTransfer(.success(element))
      )

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      return .none
    }
  }

  enum FinishAction {
    case none
    case resumeConsumer(continuation: SuspendedConsumer?)
  }

  mutating func finish(error: Error?) -> FinishAction {
    switch self.state {
    case .initial:
      preconditionFailure("Invalid state. The task should already by started.")

    case .buffering(_, var buffer, .none):
      // we are either idle or the buffer is already in use (no awaiting consumer)
      // if we have an error we stack it in the buffer so it can be consumed later
      if let error {
        buffer.append(.failure(error))
      }
      self.state = .finished(buffer: buffer)
      return .none

    case .buffering(_, let buffer, let suspendedConsumer):
      // we have an awaiting consumer, we can resume it with nil or the error
      precondition(buffer.isEmpty, "Invalid state. The buffer should be empty.")
      self.state = .finished(buffer: [])
      return .resumeConsumer(continuation: suspendedConsumer)

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      return .none
    }
  }

  enum NextAction {
    case startTask(base: Base)
    case suspend
    case returnResult(Result<Element, Error>?)
  }

  mutating func next() -> NextAction {
    switch self.state {
    case .initial(let base):
      return .startTask(base: base)

    case .buffering(_, let buffer, let suspendedConsumer) where buffer.isEmpty:
      // we are idle, we have to suspend the consumer
      precondition(suspendedConsumer == nil, "Invalid states. There is already a suspended consumer.")
      return .suspend

    case .buffering(let task, var buffer, let suspendedConsumer):
      // the buffer is already in use, we can unstack a value and directly resume the consumer
      precondition(suspendedConsumer == nil, "Invalid states. There is already a suspended consumer.")
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .buffering(task: task, buffer: buffer, suspendedConsumer: nil)
      return .returnResult(result.map { $0.wrapped })

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished(let buffer) where buffer.isEmpty:
      return .returnResult(nil)

    case .finished(var buffer):
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .finished(buffer: buffer)
      return .returnResult(result.map { $0.wrapped })
    }
  }

  enum NextSuspendedAction {
    case none
    case resumeConsumer(Result<Element, Error>?)
  }

  mutating func nextSuspended(continuation: SuspendedConsumer) -> NextSuspendedAction {
    switch self.state {
    case .initial:
      preconditionFailure("Invalid state. The task should already by started.")

    case .buffering(let task, let buffer, let suspendedConsumer) where buffer.isEmpty:
      // we are idle, we confirm the suspension of the consumer
      precondition(suspendedConsumer == nil, "Invalid states. There is already a suspended consumer.")
      self.state = .buffering(task: task, buffer: buffer, suspendedConsumer: continuation)
      return .none

    case .buffering(let task, var buffer, let suspendedConsumer):
      // the buffer is already in use, we can unstack a value and directly resume the consumer
      precondition(suspendedConsumer == nil, "Invalid states. There is already a suspended consumer.")
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .buffering(task: task, buffer: buffer, suspendedConsumer: nil)
      return .resumeConsumer(result.map { $0.wrapped })

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished(let buffer) where buffer.isEmpty:
      return .resumeConsumer(nil)

    case .finished(var buffer):
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .finished(buffer: buffer)
      return .resumeConsumer(result.map { $0.wrapped })
    }
  }

  enum InterruptedAction {
    case none
    case resumeConsumer(task: Task<Void, Never>, continuation: SuspendedConsumer?)
  }

  mutating func interrupted() -> InterruptedAction {
    switch self.state {
    case .initial:
      state = .finished(buffer: [])
      return .none

    case .buffering(let task, _, let suspendedConsumer):
      self.state = .finished(buffer: [])
      return .resumeConsumer(task: task, continuation: suspendedConsumer)

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      self.state = .finished(buffer: [])
      return .none
    }
  }
}

@available(AsyncAlgorithms 1.0, *)
extension UnboundedBufferStateMachine: Sendable where Base: Sendable {}
@available(AsyncAlgorithms 1.0, *)
extension UnboundedBufferStateMachine.State: Sendable where Base: Sendable {}

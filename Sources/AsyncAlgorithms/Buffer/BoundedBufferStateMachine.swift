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
struct BoundedBufferStateMachine<Base: AsyncSequence> {
  typealias Element = Base.Element
  typealias SuspendedProducer = UnsafeContinuation<Void, Never>
  typealias SuspendedConsumer = UnsafeContinuation<UnsafeTransfer<Result<Base.Element, Error>?>, Never>

  // We are using UnsafeTransfer here since we have to get the elements from the task
  // into the consumer task. This is a transfer but we cannot prove this to the compiler at this point
  // since next is not marked as transferring the return value.
  fileprivate enum State {
    case initial(base: Base)
    case buffering(
      task: Task<Void, Never>,
      buffer: Deque<Result<UnsafeTransfer<Element>, Error>>,
      suspendedProducer: SuspendedProducer?,
      suspendedConsumer: SuspendedConsumer?
    )
    case modifying
    case finished(buffer: Deque<Result<UnsafeTransfer<Element>, Error>>)
  }

  private var state: State
  private let limit: Int

  init(base: Base, limit: Int) {
    self.state = .initial(base: base)
    self.limit = limit
  }

  var task: Task<Void, Never>? {
    switch self.state {
    case .buffering(let task, _, _, _):
      return task
    default:
      return nil
    }
  }

  mutating func taskStarted(task: Task<Void, Never>) {
    switch self.state {
    case .initial:
      self.state = .buffering(task: task, buffer: [], suspendedProducer: nil, suspendedConsumer: nil)

    case .buffering:
      preconditionFailure("Invalid state.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      preconditionFailure("Invalid state.")
    }
  }

  mutating func shouldSuspendProducer() -> Bool {
    switch state {
    case .initial:
      preconditionFailure("Invalid state. The task should already be started.")

    case .buffering(_, let buffer, .none, .none):
      // we are either idle or the buffer is already in use (no awaiting consumer)
      // if there are free slots, we should directly request the next element
      return buffer.count >= self.limit

    case .buffering(_, _, .none, .some):
      // we have an awaiting consumer, we should not suspended the producer, we should
      // directly request the next element
      return false

    case .buffering(_, _, .some, _):
      preconditionFailure("Invalid state. There is already a suspended producer.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      return false
    }
  }

  enum ProducerSuspendedAction {
    case none
    case resumeProducer
  }

  mutating func producerSuspended(continuation: SuspendedProducer) -> ProducerSuspendedAction {
    switch self.state {
    case .initial:
      preconditionFailure("Invalid state. The task should already be started.")

    case .buffering(let task, let buffer, .none, .none):
      // we are either idle or the buffer is already in use (no awaiting consumer)
      // if the buffer is available we resume the producer so it can we can request the next element
      // otherwise we confirm the suspension
      guard buffer.count < limit else {
        self.state = .buffering(
          task: task,
          buffer: buffer,
          suspendedProducer: continuation,
          suspendedConsumer: nil
        )
        return .none
      }
      return .resumeProducer

    case .buffering(_, let buffer, .none, .some):
      // we have an awaiting consumer, we can resume the producer so the next element can be requested
      precondition(
        buffer.isEmpty,
        "Invalid state. The buffer should be empty as we have an awaiting consumer already."
      )
      return .resumeProducer

    case .buffering(_, _, .some, _):
      preconditionFailure("Invalid state. There is already a suspended producer.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      return .resumeProducer
    }
  }

  enum ElementProducedAction {
    case none
    case resumeConsumer(continuation: SuspendedConsumer, result: UnsafeTransfer<Result<Base.Element, Error>?>)
  }

  mutating func elementProduced(element: Element) -> ElementProducedAction {
    switch self.state {
    case .initial:
      preconditionFailure("Invalid state. The task should already be started.")

    case .buffering(let task, var buffer, .none, .none):
      // we are either idle or the buffer is already in use (no awaiting consumer)
      // we have to stack the new element or suspend the producer if the buffer is full
      precondition(
        buffer.count < limit,
        "Invalid state. The buffer should be available for stacking a new element."
      )
      self.state = .modifying
      buffer.append(.success(.init(element)))
      self.state = .buffering(task: task, buffer: buffer, suspendedProducer: nil, suspendedConsumer: nil)
      return .none

    case .buffering(let task, let buffer, .none, .some(let suspendedConsumer)):
      // we have an awaiting consumer, we can resume it with the element and exit
      precondition(buffer.isEmpty, "Invalid state. The buffer should be empty.")
      self.state = .buffering(task: task, buffer: buffer, suspendedProducer: nil, suspendedConsumer: nil)
      return .resumeConsumer(continuation: suspendedConsumer, result: UnsafeTransfer(.success(element)))

    case .buffering(_, _, .some, _):
      preconditionFailure("Invalid state. There should not be a suspended producer.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      return .none
    }
  }

  enum FinishAction {
    case none
    case resumeConsumer(
      continuation: UnsafeContinuation<UnsafeTransfer<Result<Base.Element, Error>?>, Never>?
    )
  }

  mutating func finish(error: Error?) -> FinishAction {
    switch self.state {
    case .initial:
      preconditionFailure("Invalid state. The task should already be started.")

    case .buffering(_, var buffer, .none, .none):
      // we are either idle or the buffer is already in use (no awaiting consumer)
      // if we have an error we stack it in the buffer so it can be consumed later
      if let error {
        buffer.append(.failure(error))
      }
      self.state = .finished(buffer: buffer)
      return .none

    case .buffering(_, let buffer, .none, .some(let suspendedConsumer)):
      // we have an awaiting consumer, we can resume it
      precondition(buffer.isEmpty, "Invalid state. The buffer should be empty.")
      self.state = .finished(buffer: [])
      return .resumeConsumer(continuation: suspendedConsumer)

    case .buffering(_, _, .some, _):
      preconditionFailure("Invalid state. There should not be a suspended producer.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      return .none
    }
  }

  enum NextAction {
    case startTask(base: Base)
    case suspend
    case returnResult(producerContinuation: UnsafeContinuation<Void, Never>?, result: Result<Element, Error>?)
  }

  mutating func next() -> NextAction {
    switch state {
    case .initial(let base):
      return .startTask(base: base)

    case .buffering(_, let buffer, .none, .none) where buffer.isEmpty:
      // we are idle, we must suspend the consumer
      return .suspend

    case .buffering(let task, var buffer, let suspendedProducer, .none):
      // we have values in the buffer, we unstack the oldest one and resume a potential suspended producer
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .buffering(task: task, buffer: buffer, suspendedProducer: nil, suspendedConsumer: nil)
      return .returnResult(producerContinuation: suspendedProducer, result: result.map { $0.wrapped })

    case .buffering(_, _, _, .some):
      preconditionFailure("Invalid states. There is already a suspended consumer.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished(let buffer) where buffer.isEmpty:
      return .returnResult(producerContinuation: nil, result: nil)

    case .finished(var buffer):
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .finished(buffer: buffer)
      return .returnResult(producerContinuation: nil, result: result.map { $0.wrapped })
    }
  }

  enum NextSuspendedAction {
    case none
    case returnResult(producerContinuation: UnsafeContinuation<Void, Never>?, result: Result<Element, Error>?)
  }

  mutating func nextSuspended(continuation: SuspendedConsumer) -> NextSuspendedAction {
    switch self.state {
    case .initial:
      preconditionFailure("Invalid state. The task should already be started.")

    case .buffering(let task, let buffer, .none, .none) where buffer.isEmpty:
      // we are idle, we confirm the suspension of the consumer
      self.state = .buffering(task: task, buffer: buffer, suspendedProducer: nil, suspendedConsumer: continuation)
      return .none

    case .buffering(let task, var buffer, let suspendedProducer, .none):
      // we have values in the buffer, we unstack the oldest one and resume a potential suspended producer
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .buffering(task: task, buffer: buffer, suspendedProducer: nil, suspendedConsumer: nil)
      return .returnResult(producerContinuation: suspendedProducer, result: result.map { $0.wrapped })

    case .buffering(_, _, _, .some):
      preconditionFailure("Invalid states. There is already a suspended consumer.")

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished(let buffer) where buffer.isEmpty:
      return .returnResult(producerContinuation: nil, result: nil)

    case .finished(var buffer):
      self.state = .modifying
      let result = buffer.popFirst()!
      self.state = .finished(buffer: buffer)
      return .returnResult(producerContinuation: nil, result: result.map { $0.wrapped })
    }
  }

  enum InterruptedAction {
    case none
    case resumeProducerAndConsumer(
      task: Task<Void, Never>,
      producerContinuation: UnsafeContinuation<Void, Never>?,
      consumerContinuation: UnsafeContinuation<UnsafeTransfer<Result<Base.Element, Error>?>, Never>?
    )
  }

  mutating func interrupted() -> InterruptedAction {
    switch self.state {
    case .initial:
      self.state = .finished(buffer: [])
      return .none

    case .buffering(let task, _, let suspendedProducer, let suspendedConsumer):
      self.state = .finished(buffer: [])
      return .resumeProducerAndConsumer(
        task: task,
        producerContinuation: suspendedProducer,
        consumerContinuation: suspendedConsumer
      )

    case .modifying:
      preconditionFailure("Invalid state.")

    case .finished:
      self.state = .finished(buffer: [])
      return .none
    }
  }
}

@available(AsyncAlgorithms 1.0, *)
extension BoundedBufferStateMachine: Sendable where Base: Sendable {}
@available(AsyncAlgorithms 1.0, *)
extension BoundedBufferStateMachine.State: Sendable where Base: Sendable {}

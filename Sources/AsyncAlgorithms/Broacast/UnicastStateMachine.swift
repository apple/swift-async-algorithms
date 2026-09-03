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

@_implementationOnly import DequeModule

struct UnicastStateMachine<Element>: Sendable {
  enum State {
    case buffering(
      elements: Deque<Result<Element?, Error>>,
      suspendedConsumer: UnsafeContinuation<Result<Element?, Error>, Never>?
    )
    case finished(elements: Deque<Result<Element?, Error>>)
  }

  private var state: State = .buffering(elements: [], suspendedConsumer: nil)

  enum SendAction {
    case none
    case resumeConsumer(continuation: UnsafeContinuation<Result<Element?, Error>, Never>?)
  }

  mutating func send(_ element: Element) -> SendAction {
    switch self.state {
      case .buffering(let elements, let suspendedConsumer) where suspendedConsumer != nil:
        // we are waiting for a producer, we can resume the awaiting consumer
        self.state = .buffering(elements: elements, suspendedConsumer: nil)
        return .resumeConsumer(continuation: suspendedConsumer)
      case .buffering(var elements, _):
        elements.append(.success(element))
        self.state = .buffering(elements: elements, suspendedConsumer: nil)
        return .none
      case .finished:
        return .none
    }
  }

  enum FinishAction {
    case none
    case resumeConsumer(continuation: UnsafeContinuation<Result<Element?, Error>, Never>?, error: Error?)
  }

  mutating func finish(error: Error?) -> FinishAction {
    switch self.state {
      case .buffering(_, let suspendedConsumer) where suspendedConsumer != nil:
        // we are waiting for a producer, we can resume the awaiting consumer with nil
        self.state = .finished(elements: [])
        return .resumeConsumer(continuation: suspendedConsumer, error: error)
      case .buffering(var elements, _):
        if let error {
          elements.append(.failure(error))
        }
        self.state = .finished(elements: elements)
        return .none
      case .finished:
        return .none
    }
  }

  enum NextAction {
    case suspend
    case exit(element: Result<Element?, Error>)
  }

  mutating func next() -> NextAction {
    switch self.state {
      case .buffering(var elements, _) where !elements.isEmpty:
        // we have stacked values, we deliver the first to the iteration
        let element = elements.popFirst()!
        self.state = .buffering(elements: elements, suspendedConsumer: nil)
        return .exit(element: element)
      case .buffering(_, let suspendedConsumer) where suspendedConsumer != nil:
        // a consumer is already suspended, this is an error
        preconditionFailure("Invalid state. A consumer is already suspended")
      case .buffering(_, _):
        return .suspend
      case .finished(var elements) where !elements.isEmpty:
        let element = elements.popFirst()!
        self.state = .finished(elements: elements)
        return .exit(element: element)
      case .finished:
        return .exit(element: .success(nil))
    }
  }

  enum NextIsSuspendedAction {
    case resume(element: Result<Element?, Error>)
    case suspend
  }

  mutating func nextIsSuspended(
    continuation: UnsafeContinuation<Result<Element?, Error>, Never>
  ) -> NextIsSuspendedAction {
    switch self.state {
      case .buffering(var elements, _) where !elements.isEmpty:
        // we have stacked values, we resume the continuation with the first element
        let element = elements.popFirst()!
        self.state = .buffering(elements: elements, suspendedConsumer: nil)
        return .resume(element: element)
      case .buffering(_, let suspendedConsumer) where suspendedConsumer != nil:
        // a consumer is already suspended, this is an error
        preconditionFailure("Invalid state. A consumer is already suspended")
      case .buffering(let elements, _):
        // we suspend the consumer
        self.state = .buffering(elements: elements, suspendedConsumer: continuation)
        return .suspend
      case .finished(var elements) where !elements.isEmpty:
        let element = elements.popFirst()!
        self.state = .finished(elements: elements)
        return .resume(element: element)
      case .finished:
        return .resume(element: .success(nil))
    }
  }

  mutating func nextIsCancelled() -> UnsafeContinuation<Result<Element?, Error>, Never>? {
    switch self.state {
      case .buffering(_, let suspendedConsumer):
        self.state = .finished(elements: [])
        return suspendedConsumer
      case .finished:
        return nil
    }
  }
}

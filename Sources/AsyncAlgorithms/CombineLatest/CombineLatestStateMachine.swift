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

/// State machine for combine latest
@available(AsyncAlgorithms 1.0, *)
struct CombineLatestStateMachine<
  Base1: AsyncSequence,
  Base2: AsyncSequence,
  Base3: AsyncSequence
>: Sendable
where
  Base1: Sendable,
  Base2: Sendable,
  Base3: Sendable,
  Base1.Element: Sendable,
  Base2.Element: Sendable,
  Base3.Element: Sendable
{
  typealias DownstreamContinuation = UnsafeContinuation<
    Result<
      (
        Base1.Element,
        Base2.Element,
        Base3.Element?
      )?, Error
    >, Never
  >

  private enum State: Sendable {
    /// Small wrapper for the state of an upstream sequence.
    struct Upstream<Element: Sendable>: Sendable {
      /// The upstream continuation.
      var continuation: UnsafeContinuation<Void, Error>?
      /// The produced upstream element.
      var element: Element?
      /// Indicates wether the upstream finished/threw already
      var isFinished: Bool
    }

    /// The initial state before a call to `next` happened.
    case initial(base1: Base1, base2: Base2, base3: Base3?)

    /// The state while we are waiting for downstream demand.
    case waitingForDemand(
      task: Task<Void, Never>,
      upstreams: (Upstream<Base1.Element>, Upstream<Base2.Element>, Upstream<Base3.Element>),
      buffer: Deque<(Base1.Element, Base2.Element, Base3.Element?)>
    )

    /// The state while we are consuming the upstream and waiting until we get a result from all upstreams.
    case combining(
      task: Task<Void, Never>,
      upstreams: (Upstream<Base1.Element>, Upstream<Base2.Element>, Upstream<Base3.Element>),
      downstreamContinuation: DownstreamContinuation,
      buffer: Deque<(Base1.Element, Base2.Element, Base3.Element?)>
    )

    case upstreamsFinished(
      buffer: Deque<(Base1.Element, Base2.Element, Base3.Element?)>
    )

    case upstreamThrew(
      error: Error
    )

    /// The state once the downstream consumer stopped, i.e. by dropping all references
    /// or by getting their `Task` cancelled.
    case finished

    /// Internal state to avoid CoW.
    case modifying
  }

  private var state: State

  private let numberOfUpstreamSequences: Int

  /// Initializes a new `StateMachine`.
  init(
    base1: Base1,
    base2: Base2,
    base3: Base3?
  ) {
    self.state = .initial(
      base1: base1,
      base2: base2,
      base3: base3
    )

    if base3 == nil {
      self.numberOfUpstreamSequences = 2
    } else {
      self.numberOfUpstreamSequences = 3
    }
  }

  /// Actions returned by `iteratorDeinitialized()`.
  enum IteratorDeinitializedAction {
    /// Indicates that the `Task` needs to be cancelled and
    /// the upstream continuations need to be resumed with a `CancellationError`.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
  }

  mutating func iteratorDeinitialized() -> IteratorDeinitializedAction? {
    switch self.state {
    case .initial:
      // Nothing to do here. No demand was signalled until now
      return .none

    case .combining:
      // An iterator was deinitialized while we have a suspended continuation.
      preconditionFailure(
        "Internal inconsistency current state \(self.state) and received iteratorDeinitialized()"
      )

    case .waitingForDemand(let task, let upstreams, _):
      // The iterator was dropped which signals that the consumer is finished.
      // We can transition to finished now and need to clean everything up.
      self.state = .finished

      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .upstreamThrew, .upstreamsFinished:
      // The iterator was dropped so we can transition to finished now.
      self.state = .finished

      return .none

    case .finished:
      // We are already finished so there is nothing left to clean up.
      // This is just the references dropping afterwards.
      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  mutating func taskIsStarted(
    task: Task<Void, Never>,
    downstreamContinuation: DownstreamContinuation
  ) {
    switch self.state {
    case .initial:
      // The user called `next` and we are starting the `Task`
      // to consume the upstream sequences
      self.state = .combining(
        task: task,
        upstreams: (.init(isFinished: false), .init(isFinished: false), .init(isFinished: false)),
        downstreamContinuation: downstreamContinuation,
        buffer: .init()
      )

    case .combining, .waitingForDemand, .upstreamThrew, .upstreamsFinished, .finished:
      // We only allow a single task to be created so this must never happen.
      preconditionFailure("Internal inconsistency current state \(self.state) and received taskStarted()")

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `childTaskSuspended()`.
  enum ChildTaskSuspendedAction {
    /// Indicates that the continuation should be resumed which will lead to calling `next` on the upstream.
    case resumeContinuation(
      upstreamContinuation: UnsafeContinuation<Void, Error>
    )
    /// Indicates that the continuation should be resumed with an Error because another upstream sequence threw.
    case resumeContinuationWithError(
      upstreamContinuation: UnsafeContinuation<Void, Error>,
      error: Error
    )
  }

  mutating func childTaskSuspended(
    baseIndex: Int,
    continuation: UnsafeContinuation<Void, Error>
  ) -> ChildTaskSuspendedAction? {
    switch self.state {
    case .initial:
      // Child tasks are only created after we transitioned to `zipping`
      preconditionFailure("Internal inconsistency current state \(self.state) and received childTaskSuspended()")

    case .upstreamsFinished:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamThrew()")

    case .waitingForDemand(let task, var upstreams, let buffer):
      self.state = .modifying

      switch baseIndex {
      case 0:
        upstreams.0.continuation = continuation

      case 1:
        upstreams.1.continuation = continuation

      case 2:
        upstreams.2.continuation = continuation

      default:
        preconditionFailure(
          "Internal inconsistency current state \(self.state) and received childTaskSuspended() with base index \(baseIndex)"
        )
      }

      self.state = .waitingForDemand(
        task: task,
        upstreams: upstreams,
        buffer: buffer
      )

      return .none

    case .combining:
      // We are currently combining and need to resume any upstream until we transition to waitingForDemand

      return .resumeContinuation(upstreamContinuation: continuation)

    case .upstreamThrew, .finished:
      // Since cancellation is cooperative it might be that child tasks are still getting
      // suspended even though we already cancelled them. We must tolerate this and just resume
      // the continuation with an error.
      return .resumeContinuationWithError(
        upstreamContinuation: continuation,
        error: CancellationError()
      )

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `elementProduced()`.
  enum ElementProducedAction {
    /// Indicates that the downstream continuation should be resumed with the element.
    case resumeContinuation(
      downstreamContinuation: DownstreamContinuation,
      result: Result<(Base1.Element, Base2.Element, Base3.Element?)?, Error>
    )
  }

  mutating func elementProduced(_ result: (Base1.Element?, Base2.Element?, Base3.Element?)) -> ElementProducedAction? {
    switch self.state {
    case .initial:
      // Child tasks that are producing elements are only created after we transitioned to `zipping`
      preconditionFailure("Internal inconsistency current state \(self.state) and received elementProduced()")

    case .upstreamsFinished:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamThrew()")

    case .waitingForDemand(let task, var upstreams, var buffer):
      // We got an element in late. This can happen since we race the upstreams.
      // We have to store the new tuple in our buffer and remember the upstream states.

      self.state = .modifying

      switch result {
      case (.some(let first), .none, .none):
        buffer.append((first, upstreams.1.element!, upstreams.2.element))
        upstreams.0.element = first

      case (.none, .some(let second), .none):
        buffer.append((upstreams.0.element!, second, upstreams.2.element))
        upstreams.1.element = second

      case (.none, .none, .some(let third)):
        buffer.append((upstreams.0.element!, upstreams.1.element!, third))
        upstreams.2.element = third

      default:
        preconditionFailure("Internal inconsistency current state \(self.state) and received elementProduced()")
      }

      self.state = .waitingForDemand(
        task: task,
        upstreams: upstreams,
        buffer: buffer
      )

      return .none

    case .combining(let task, var upstreams, let downstreamContinuation, let buffer):
      precondition(
        buffer.isEmpty,
        "Internal inconsistency current state \(self.state) and the buffer is not empty"
      )
      self.state = .modifying

      switch result {
      case (.some(let first), .none, .none):
        upstreams.0.element = first

      case (.none, .some(let second), .none):
        upstreams.1.element = second

      case (.none, .none, .some(let third)):
        upstreams.2.element = third

      default:
        preconditionFailure("Internal inconsistency current state \(self.state) and received elementProduced()")
      }

      // Implementing this for the two arities without variadic generics is a bit awkward sadly.
      if let first = upstreams.0.element,
        let second = upstreams.1.element,
        let third = upstreams.2.element
      {
        // We got an element from each upstream so we can resume the downstream now
        self.state = .waitingForDemand(
          task: task,
          upstreams: upstreams,
          buffer: buffer
        )

        return .resumeContinuation(
          downstreamContinuation: downstreamContinuation,
          result: .success((first, second, third))
        )

      } else if let first = upstreams.0.element,
        let second = upstreams.1.element,
        self.numberOfUpstreamSequences == 2
      {
        // We got an element from each upstream so we can resume the downstream now
        self.state = .waitingForDemand(
          task: task,
          upstreams: upstreams,
          buffer: buffer
        )

        return .resumeContinuation(
          downstreamContinuation: downstreamContinuation,
          result: .success((first, second, nil))
        )
      } else {
        // We are still waiting for one of the upstreams to produce an element
        self.state = .combining(
          task: task,
          upstreams: (
            .init(
              continuation: upstreams.0.continuation,
              element: upstreams.0.element,
              isFinished: upstreams.0.isFinished
            ),
            .init(
              continuation: upstreams.1.continuation,
              element: upstreams.1.element,
              isFinished: upstreams.1.isFinished
            ),
            .init(
              continuation: upstreams.2.continuation,
              element: upstreams.2.element,
              isFinished: upstreams.2.isFinished
            )
          ),
          downstreamContinuation: downstreamContinuation,
          buffer: buffer
        )

        return .none
      }

    case .upstreamThrew, .finished:
      // Since cancellation is cooperative it might be that child tasks
      // are still producing elements after we finished.
      // We are just going to drop them since there is nothing we can do
      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `upstreamFinished()`.
  enum UpstreamFinishedAction {
    /// Indicates the task and the upstream continuations should be cancelled.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that the downstream continuation should be resumed with `nil` and
    /// the task and the upstream continuations should be cancelled.
    case resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
      downstreamContinuation: DownstreamContinuation,
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
  }

  mutating func upstreamFinished(baseIndex: Int) -> UpstreamFinishedAction? {
    switch self.state {
    case .initial:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")

    case .upstreamsFinished:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")

    case .waitingForDemand(let task, var upstreams, let buffer):
      // One of the upstreams finished.

      self.state = .modifying

      switch baseIndex {
      case 0:
        upstreams.0.isFinished = true

      case 1:
        upstreams.1.isFinished = true

      case 2:
        upstreams.2.isFinished = true

      default:
        preconditionFailure(
          "Internal inconsistency current state \(self.state) and received upstreamFinished() with base index \(baseIndex)"
        )
      }

      if upstreams.0.isFinished && upstreams.1.isFinished && upstreams.2.isFinished {
        // All upstreams finished we can transition to either finished or upstreamsFinished now
        if buffer.isEmpty {
          self.state = .finished
        } else {
          self.state = .upstreamsFinished(buffer: buffer)
        }

        return .cancelTaskAndUpstreamContinuations(
          task: task,
          upstreamContinuations: [
            upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation,
          ].compactMap { $0 }
        )
      } else if upstreams.0.isFinished && upstreams.1.isFinished && self.numberOfUpstreamSequences == 2 {
        // All upstreams finished we can transition to either finished or upstreamsFinished now
        if buffer.isEmpty {
          self.state = .finished
        } else {
          self.state = .upstreamsFinished(buffer: buffer)
        }

        return .cancelTaskAndUpstreamContinuations(
          task: task,
          upstreamContinuations: [
            upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation,
          ].compactMap { $0 }
        )
      } else {
        self.state = .waitingForDemand(
          task: task,
          upstreams: upstreams,
          buffer: buffer
        )
        return .none
      }

    case .combining(let task, var upstreams, let downstreamContinuation, let buffer):
      // One of the upstreams finished.

      self.state = .modifying

      // We need to track if an empty upstream finished.
      // If that happens we can transition to finish right away.
      let emptyUpstreamFinished: Bool
      switch baseIndex {
      case 0:
        upstreams.0.isFinished = true
        emptyUpstreamFinished = upstreams.0.element == nil

      case 1:
        upstreams.1.isFinished = true
        emptyUpstreamFinished = upstreams.1.element == nil

      case 2:
        upstreams.2.isFinished = true
        emptyUpstreamFinished = upstreams.2.element == nil

      default:
        preconditionFailure(
          "Internal inconsistency current state \(self.state) and received upstreamFinished() with base index \(baseIndex)"
        )
      }

      // Implementing this for the two arities without variadic generics is a bit awkward sadly.
      if emptyUpstreamFinished {
        // All upstreams finished
        self.state = .finished

        return .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
          downstreamContinuation: downstreamContinuation,
          task: task,
          upstreamContinuations: [
            upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation,
          ].compactMap { $0 }
        )

      } else if upstreams.0.isFinished && upstreams.1.isFinished && upstreams.2.isFinished {
        // All upstreams finished
        self.state = .finished

        return .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
          downstreamContinuation: downstreamContinuation,
          task: task,
          upstreamContinuations: [
            upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation,
          ].compactMap { $0 }
        )

      } else if upstreams.0.isFinished && upstreams.1.isFinished && self.numberOfUpstreamSequences == 2 {
        // All upstreams finished
        self.state = .finished

        return .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
          downstreamContinuation: downstreamContinuation,
          task: task,
          upstreamContinuations: [
            upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation,
          ].compactMap { $0 }
        )
      } else {
        self.state = .combining(
          task: task,
          upstreams: upstreams,
          downstreamContinuation: downstreamContinuation,
          buffer: buffer
        )
        return .none
      }

    case .upstreamThrew, .finished:
      // This is just everything finishing up, nothing to do here
      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `upstreamThrew()`.
  enum UpstreamThrewAction {
    /// Indicates the task and the upstream continuations should be cancelled.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that the downstream continuation should be resumed with the `error` and
    /// the task and the upstream continuations should be cancelled.
    case resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
      downstreamContinuation: DownstreamContinuation,
      error: Error,
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
  }

  mutating func upstreamThrew(_ error: Error) -> UpstreamThrewAction? {
    switch self.state {
    case .initial:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamThrew()")

    case .upstreamsFinished:
      // We need to tolerate multiple upstreams failing
      return .none

    case .waitingForDemand(let task, let upstreams, _):
      // An upstream threw. We can cancel everything now and transition to finished.
      // We just need to store the error for the next downstream demand
      self.state = .upstreamThrew(
        error: error
      )

      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .combining(let task, let upstreams, let downstreamContinuation, _):
      // One of our upstreams threw. We need to transition to finished ourselves now
      // and resume the downstream continuation with the error. Furthermore, we need to cancel all of
      // the upstream work.
      self.state = .finished

      return .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
        downstreamContinuation: downstreamContinuation,
        error: error,
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .upstreamThrew, .finished:
      // This is just everything finishing up, nothing to do here
      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `cancelled()`.
  enum CancelledAction {
    /// Indicates that the downstream continuation needs to be resumed and
    /// task and the upstream continuations should be cancelled.
    case resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
      downstreamContinuation: DownstreamContinuation,
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that the task and the upstream continuations should be cancelled.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
  }

  mutating func cancelled() -> CancelledAction? {
    switch self.state {
    case .initial:
      state = .finished

      return .none

    case .waitingForDemand(let task, let upstreams, _):
      // The downstream task got cancelled so we need to cancel our upstream Task
      // and resume all continuations. We can also transition to finished.
      self.state = .finished

      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .combining(let task, let upstreams, let downstreamContinuation, _):
      // The downstream Task got cancelled so we need to cancel our upstream Task
      // and resume all continuations. We can also transition to finished.
      self.state = .finished

      return .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .upstreamsFinished:
      // We can transition to finished now
      self.state = .finished

      return .none

    case .upstreamThrew, .finished:
      // We are already finished so nothing to do here:

      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `next()`.
  enum NextAction {
    /// Indicates that a new `Task` should be created that consumes the sequence.
    case startTask(Base1, Base2, Base3?)
    /// Indicates that all upstream continuations should be resumed.
    case resumeUpstreamContinuations(
      upstreamContinuation: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that the downstream continuation should be resumed with the result.
    case resumeContinuation(
      downstreamContinuation: DownstreamContinuation,
      result: Result<(Base1.Element, Base2.Element, Base3.Element?)?, Error>
    )
    /// Indicates that the downstream continuation should be resumed with `nil`.
    case resumeDownstreamContinuationWithNil(DownstreamContinuation)
  }

  mutating func next(for continuation: DownstreamContinuation) -> NextAction {
    switch self.state {
    case .initial(let base1, let base2, let base3):
      // This is the first time we get demand singalled so we have to start the task
      // The transition to the next state is done in the taskStarted method
      return .startTask(base1, base2, base3)

    case .combining:
      // We already got demand signalled and have suspended the downstream task
      // Getting a second next calls means the iterator was transferred across Tasks which is not allowed
      preconditionFailure("Internal inconsistency current state \(self.state) and received next()")

    case .waitingForDemand(let task, var upstreams, var buffer):
      // We got demand signalled now we have to check if there is anything buffered.
      // If not we have to transition to combining and need to resume all upstream continuations now
      self.state = .modifying

      guard let element = buffer.popFirst() else {
        let upstreamContinuations = [
          upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation,
        ].compactMap { $0 }
        upstreams.0.continuation = nil
        upstreams.1.continuation = nil
        upstreams.2.continuation = nil

        self.state = .combining(
          task: task,
          upstreams: upstreams,
          downstreamContinuation: continuation,
          buffer: buffer
        )

        return .resumeUpstreamContinuations(
          upstreamContinuation: upstreamContinuations
        )
      }
      self.state = .waitingForDemand(
        task: task,
        upstreams: upstreams,
        buffer: buffer
      )

      return .resumeContinuation(
        downstreamContinuation: continuation,
        result: .success(element)
      )

    case .upstreamsFinished(var buffer):
      self.state = .modifying

      guard let element = buffer.popFirst() else {
        self.state = .finished

        return .resumeDownstreamContinuationWithNil(continuation)
      }
      self.state = .upstreamsFinished(buffer: buffer)

      return .resumeContinuation(
        downstreamContinuation: continuation,
        result: .success(element)
      )

    case .upstreamThrew(let error):
      // One of the upstreams threw and we have to return this error now.
      self.state = .finished

      return .resumeContinuation(downstreamContinuation: continuation, result: .failure(error))

    case .finished:
      // We are already finished so we are just returning `nil`
      return .resumeDownstreamContinuationWithNil(continuation)

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }
}

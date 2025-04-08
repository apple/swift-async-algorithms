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

/// State machine for zip
@available(AsyncAlgorithms 1.0, *)
struct ZipStateMachine<
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
    }

    /// The initial state before a call to `next` happened.
    case initial(base1: Base1, base2: Base2, base3: Base3?)

    /// The state while we are waiting for downstream demand.
    case waitingForDemand(
      task: Task<Void, Never>,
      upstreams: (Upstream<Base1.Element>, Upstream<Base2.Element>, Upstream<Base3.Element>)
    )

    /// The state while we are consuming the upstream and waiting until we get a result from all upstreams.
    case zipping(
      task: Task<Void, Never>,
      upstreams: (Upstream<Base1.Element>, Upstream<Base2.Element>, Upstream<Base3.Element>),
      downstreamContinuation: DownstreamContinuation
    )

    /// The state once one upstream sequences finished/threw or the downstream consumer stopped, i.e. by dropping all references
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

    case .zipping:
      // An iterator was deinitialized while we have a suspended continuation.
      preconditionFailure(
        "Internal inconsistency current state \(self.state) and received iteratorDeinitialized()"
      )

    case .waitingForDemand(let task, let upstreams):
      // The iterator was dropped which signals that the consumer is finished.
      // We can transition to finished now and need to clean everything up.
      self.state = .finished

      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

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
      self.state = .zipping(
        task: task,
        upstreams: (.init(), .init(), .init()),
        downstreamContinuation: downstreamContinuation
      )

    case .zipping, .waitingForDemand, .finished:
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

    case .waitingForDemand(let task, var upstreams):
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
        upstreams: upstreams
      )

      return .none

    case .zipping(let task, var upstreams, let downstreamContinuation):
      // We are currently zipping. If we have a buffered element from the base
      // already then we store the continuation otherwise we just go ahead and resume it
      switch baseIndex {
      case 0:
        guard upstreams.0.element == nil else {
          self.state = .modifying
          upstreams.0.continuation = continuation
          self.state = .zipping(
            task: task,
            upstreams: upstreams,
            downstreamContinuation: downstreamContinuation
          )
          return .none
        }
        return .resumeContinuation(upstreamContinuation: continuation)

      case 1:
        guard upstreams.1.element == nil else {
          self.state = .modifying
          upstreams.1.continuation = continuation
          self.state = .zipping(
            task: task,
            upstreams: upstreams,
            downstreamContinuation: downstreamContinuation
          )
          return .none
        }
        return .resumeContinuation(upstreamContinuation: continuation)

      case 2:
        guard upstreams.2.element == nil else {
          self.state = .modifying
          upstreams.2.continuation = continuation
          self.state = .zipping(
            task: task,
            upstreams: upstreams,
            downstreamContinuation: downstreamContinuation
          )
          return .none
        }
        return .resumeContinuation(upstreamContinuation: continuation)

      default:
        preconditionFailure(
          "Internal inconsistency current state \(self.state) and received childTaskSuspended() with base index \(baseIndex)"
        )
      }

    case .finished:
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

    case .waitingForDemand:
      // We are only issuing demand when we get signalled by the downstream.
      // We should never receive an element when we are waiting for demand.
      preconditionFailure("Internal inconsistency current state \(self.state) and received elementProduced()")

    case .zipping(let task, var upstreams, let downstreamContinuation):
      self.state = .modifying

      switch result {
      case (.some(let first), .none, .none):
        precondition(upstreams.0.element == nil)
        upstreams.0.element = first

      case (.none, .some(let second), .none):
        precondition(upstreams.1.element == nil)
        upstreams.1.element = second

      case (.none, .none, .some(let third)):
        precondition(upstreams.2.element == nil)
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
          upstreams: (
            .init(continuation: upstreams.0.continuation),
            .init(continuation: upstreams.1.continuation),
            .init(continuation: upstreams.2.continuation)
          )
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
          upstreams: (
            .init(continuation: upstreams.0.continuation),
            .init(continuation: upstreams.1.continuation),
            .init(continuation: upstreams.2.continuation)
          )
        )

        return .resumeContinuation(
          downstreamContinuation: downstreamContinuation,
          result: .success((first, second, nil))
        )
      } else {
        // We are still waiting for one of the upstreams to produce an element
        self.state = .zipping(
          task: task,
          upstreams: (
            .init(continuation: upstreams.0.continuation, element: upstreams.0.element),
            .init(continuation: upstreams.1.continuation, element: upstreams.1.element),
            .init(continuation: upstreams.2.continuation, element: upstreams.2.element)
          ),
          downstreamContinuation: downstreamContinuation
        )

        return .none
      }

    case .finished:
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
    /// Indicates that the downstream continuation should be resumed with `nil` and
    /// the task and the upstream continuations should be cancelled.
    case resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
      downstreamContinuation: DownstreamContinuation,
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
  }

  mutating func upstreamFinished() -> UpstreamFinishedAction? {
    switch self.state {
    case .initial:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")

    case .waitingForDemand:
      // This can't happen. We are only issuing demand for a single element each time.
      // There must never be outstanding demand to an upstream while we have no demand ourselves.
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")

    case .zipping(let task, let upstreams, let downstreamContinuation):
      // One of our upstreams finished. We need to transition to finished ourselves now
      // and resume the downstream continuation with nil. Furthermore, we need to cancel all of
      // the upstream work.
      self.state = .finished

      return .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .finished:
      // This is just everything finishing up, nothing to do here
      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `upstreamThrew()`.
  enum UpstreamThrewAction {
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

    case .waitingForDemand:
      // This can't happen. We are only issuing demand for a single element each time.
      // There must never be outstanding demand to an upstream while we have no demand ourselves.
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamThrew()")

    case .zipping(let task, let upstreams, let downstreamContinuation):
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

    case .finished:
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

    case .waitingForDemand(let task, let upstreams):
      // The downstream task got cancelled so we need to cancel our upstream Task
      // and resume all continuations. We can also transition to finished.
      self.state = .finished

      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .zipping(let task, let upstreams, let downstreamContinuation):
      // The downstream Task got cancelled so we need to cancel our upstream Task
      // and resume all continuations. We can also transition to finished.
      self.state = .finished

      return .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuations: [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
          .compactMap { $0 }
      )

    case .finished:
      // We are already finished so nothing to do here:
      self.state = .finished

      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `next()`.
  enum NextAction {
    /// Indicates that a new `Task` should be created that consumes the sequence.
    case startTask(Base1, Base2, Base3?)
    case resumeUpstreamContinuations(
      upstreamContinuation: [UnsafeContinuation<Void, Error>]
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

    case .zipping:
      // We already got demand signalled and have suspended the downstream task
      // Getting a second next calls means the iterator was transferred across Tasks which is not allowed
      preconditionFailure("Internal inconsistency current state \(self.state) and received next()")

    case .waitingForDemand(let task, var upstreams):
      // We got demand signalled now and can transition to zipping.
      // We also need to resume all upstream continuations now
      self.state = .modifying

      let upstreamContinuations = [upstreams.0.continuation, upstreams.1.continuation, upstreams.2.continuation]
        .compactMap { $0 }
      upstreams.0.continuation = nil
      upstreams.1.continuation = nil
      upstreams.2.continuation = nil

      self.state = .zipping(
        task: task,
        upstreams: upstreams,
        downstreamContinuation: continuation
      )

      return .resumeUpstreamContinuations(
        upstreamContinuation: upstreamContinuations
      )

    case .finished:
      // We are already finished so we are just returning `nil`
      return .resumeDownstreamContinuationWithNil(continuation)

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }
}

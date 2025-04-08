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

/// The state machine for any of the `merge` operator.
///
/// Right now this state machine supports 3 upstream `AsyncSequences`; however, this can easily be extended.
/// Once variadic generic land we should migrate this to use them instead.
@available(AsyncAlgorithms 1.0, *)
struct MergeStateMachine<
  Base1: AsyncSequence,
  Base2: AsyncSequence,
  Base3: AsyncSequence
>
where
  Base1.Element == Base2.Element,
  Base1.Element == Base3.Element,
  Base1: Sendable,
  Base2: Sendable,
  Base3: Sendable,
  Base1.Element: Sendable
{
  typealias Element = Base1.Element

  private enum State {
    /// The initial state before a call to `makeAsyncIterator` happened.
    case initial(
      base1: Base1,
      base2: Base2,
      base3: Base3?
    )

    /// The state after `makeAsyncIterator` was called and we created our `Task` to consume the upstream.
    case merging(
      task: Task<Void, Never>,
      buffer: Deque<Element>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>],
      upstreamsFinished: Int,
      downstreamContinuation: UnsafeContinuation<Element?, Error>?
    )

    /// The state once any of the upstream sequences threw an `Error`.
    case upstreamFailure(
      buffer: Deque<Element>,
      error: Error
    )

    /// The state once all upstream sequences finished or the downstream consumer stopped, i.e. by dropping all references
    /// or by getting their `Task` cancelled.
    case finished

    /// Internal state to avoid CoW.
    case modifying
  }

  /// The state machine's current state.
  private var state: State

  private let numberOfUpstreamSequences: Int

  /// Initializes a new `StateMachine`.
  init(
    base1: Base1,
    base2: Base2,
    base3: Base3?
  ) {
    state = .initial(
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
    /// all upstream continuations need to be resumed with a `CancellationError`.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that nothing should be done.
    case none
  }

  mutating func iteratorDeinitialized() -> IteratorDeinitializedAction {
    switch state {
    case .initial:
      // Nothing to do here. No demand was signalled until now
      return .none

    case .merging(_, _, _, _, .some):
      // An iterator was deinitialized while we have a suspended continuation.
      preconditionFailure(
        "Internal inconsistency current state \(self.state) and received iteratorDeinitialized()"
      )

    case let .merging(task, _, upstreamContinuations, _, .none):
      // The iterator was dropped which signals that the consumer is finished.
      // We can transition to finished now and need to clean everything up.
      state = .finished

      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: upstreamContinuations
      )

    case .upstreamFailure:
      // The iterator was dropped which signals that the consumer is finished.
      // We can transition to finished now. The cleanup already happened when we
      // transitioned to `upstreamFailure`.
      state = .finished

      return .none

    case .finished:
      // We are already finished so there is nothing left to clean up.
      // This is just the references dropping afterwards.
      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  mutating func taskStarted(_ task: Task<Void, Never>) {
    switch state {
    case .initial:
      // The user called `makeAsyncIterator` and we are starting the `Task`
      // to consume the upstream sequences
      state = .merging(
        task: task,
        buffer: .init(),
        upstreamContinuations: [],  // This should reserve capacity in the variadic generics case
        upstreamsFinished: 0,
        downstreamContinuation: nil
      )

    case .merging, .upstreamFailure, .finished:
      // We only a single iterator to be created so this must never happen.
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
    /// Indicates that nothing should be done.
    case none
  }

  mutating func childTaskSuspended(_ continuation: UnsafeContinuation<Void, Error>) -> ChildTaskSuspendedAction {
    switch state {
    case .initial:
      // Child tasks are only created after we transitioned to `merging`
      preconditionFailure("Internal inconsistency current state \(self.state) and received childTaskSuspended()")

    case .merging(_, _, _, _, .some):
      // We have outstanding demand so request the next element
      return .resumeContinuation(upstreamContinuation: continuation)

    case .merging(let task, let buffer, var upstreamContinuations, let upstreamsFinished, .none):
      // There is no outstanding demand from the downstream
      // so we are storing the continuation and resume it once there is demand.
      state = .modifying

      upstreamContinuations.append(continuation)

      state = .merging(
        task: task,
        buffer: buffer,
        upstreamContinuations: upstreamContinuations,
        upstreamsFinished: upstreamsFinished,
        downstreamContinuation: nil
      )

      return .none

    case .upstreamFailure:
      // Another upstream already threw so we just need to throw from this continuation
      // which will end the consumption of the upstream.

      return .resumeContinuationWithError(
        upstreamContinuation: continuation,
        error: CancellationError()
      )

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
      downstreamContinuation: UnsafeContinuation<Element?, Error>,
      element: Element
    )
    /// Indicates that nothing should be done.
    case none
  }

  mutating func elementProduced(_ element: Element) -> ElementProducedAction {
    switch state {
    case .initial:
      // Child tasks that are producing elements are only created after we transitioned to `merging`
      preconditionFailure("Internal inconsistency current state \(self.state) and received elementProduced()")

    case let .merging(task, buffer, upstreamContinuations, upstreamsFinished, .some(downstreamContinuation)):
      // We produced an element and have an outstanding downstream continuation
      // this means we can go right ahead and resume the continuation with that element
      precondition(buffer.isEmpty, "We are holding a continuation so the buffer must be empty")

      state = .merging(
        task: task,
        buffer: buffer,
        upstreamContinuations: upstreamContinuations,
        upstreamsFinished: upstreamsFinished,
        downstreamContinuation: nil
      )

      return .resumeContinuation(
        downstreamContinuation: downstreamContinuation,
        element: element
      )

    case .merging(let task, var buffer, let upstreamContinuations, let upstreamsFinished, .none):
      // There is not outstanding downstream continuation so we must buffer the element
      // This happens if we race our upstream sequences to produce elements
      // and the _losers_ are signalling their produced element
      state = .modifying

      buffer.append(element)

      state = .merging(
        task: task,
        buffer: buffer,
        upstreamContinuations: upstreamContinuations,
        upstreamsFinished: upstreamsFinished,
        downstreamContinuation: nil
      )

      return .none

    case .upstreamFailure:
      // Another upstream already produced an error so we just drop the new element
      return .none

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
    /// Indicates that the task and the upstream continuations should be cancelled.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that the downstream continuation should be resumed with `nil` and
    /// the task and the upstream continuations should be cancelled.
    case resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
      downstreamContinuation: UnsafeContinuation<Element?, Error>,
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that nothing should be done.
    case none
  }

  mutating func upstreamFinished() -> UpstreamFinishedAction {
    switch state {
    case .initial:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")

    case .merging(
      let task,
      let buffer,
      let upstreamContinuations,
      var upstreamsFinished,
      let .some(downstreamContinuation)
    ):
      // One of the upstreams finished
      precondition(buffer.isEmpty, "We are holding a continuation so the buffer must be empty")

      // First we increment our counter of finished upstreams
      upstreamsFinished += 1

      guard upstreamsFinished == self.numberOfUpstreamSequences else {
        // There are still upstreams that haven't finished so we are just storing our new
        // counter of finished upstreams
        state = .merging(
          task: task,
          buffer: buffer,
          upstreamContinuations: upstreamContinuations,
          upstreamsFinished: upstreamsFinished,
          downstreamContinuation: downstreamContinuation
        )

        return .none
      }
      // All of our upstreams have finished and we can transition to finished now
      // We also need to cancel the tasks and any outstanding continuations
      state = .finished

      return .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuations: upstreamContinuations
      )

    case .merging(let task, let buffer, let upstreamContinuations, var upstreamsFinished, .none):
      // First we increment our counter of finished upstreams
      upstreamsFinished += 1

      state = .merging(
        task: task,
        buffer: buffer,
        upstreamContinuations: upstreamContinuations,
        upstreamsFinished: upstreamsFinished,
        downstreamContinuation: nil
      )

      guard upstreamsFinished == self.numberOfUpstreamSequences else {
        // There are still upstreams that haven't finished.
        return .none
      }
      // All of our upstreams have finished; however, we are only transitioning to
      // finished once our downstream calls `next` again.
      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: upstreamContinuations
      )

    case .upstreamFailure:
      // Another upstream threw already so we can just ignore this finish
      return .none

    case .finished:
      // This is just everything finishing up, nothing to do here
      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `upstreamThrew()`.
  enum UpstreamThrewAction {
    /// Indicates that the task and the upstream continuations should be cancelled.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that the downstream continuation should be resumed with the `error` and
    /// the task and the upstream continuations should be cancelled.
    case resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
      downstreamContinuation: UnsafeContinuation<Element?, Error>,
      error: Error,
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that nothing should be done.
    case none
  }

  mutating func upstreamThrew(_ error: Error) -> UpstreamThrewAction {
    switch state {
    case .initial:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamThrew()")

    case let .merging(task, buffer, upstreamContinuations, _, .some(downstreamContinuation)):
      // An upstream threw an error and we have a downstream continuation.
      // We just need to resume the downstream continuation with the error and cancel everything
      precondition(buffer.isEmpty, "We are holding a continuation so the buffer must be empty")

      // We can transition to finished right away because we are returning the error
      state = .finished

      return .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
        downstreamContinuation: downstreamContinuation,
        error: error,
        task: task,
        upstreamContinuations: upstreamContinuations
      )

    case let .merging(task, buffer, upstreamContinuations, _, .none):
      // An upstream threw an error and we don't have a downstream continuation.
      // We need to store the error and wait for the downstream to consume the
      // rest of the buffer and the error. However, we can already cancel the task
      // and the other upstream continuations since we won't need any more elements.
      state = .upstreamFailure(
        buffer: buffer,
        error: error
      )
      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: upstreamContinuations
      )

    case .upstreamFailure:
      // Another upstream threw already so we can just ignore this error
      return .none

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
      downstreamContinuation: UnsafeContinuation<Element?, Error>,
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that the task and the upstream continuations should be cancelled.
    case cancelTaskAndUpstreamContinuations(
      task: Task<Void, Never>,
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
    /// Indicates that nothing should be done.
    case none
  }

  mutating func cancelled() -> CancelledAction {
    switch state {
    case .initial:
      // Since we are only transitioning to merging when the task is started we
      // can be cancelled already.
      state = .finished

      return .none

    case let .merging(task, _, upstreamContinuations, _, .some(downstreamContinuation)):
      // The downstream Task got cancelled so we need to cancel our upstream Task
      // and resume all continuations. We can also transition to finished.
      state = .finished

      return .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuations: upstreamContinuations
      )

    case let .merging(task, _, upstreamContinuations, _, .none):
      // The downstream Task got cancelled so we need to cancel our upstream Task
      // and resume all continuations. We can also transition to finished.
      state = .finished

      return .cancelTaskAndUpstreamContinuations(
        task: task,
        upstreamContinuations: upstreamContinuations
      )

    case .upstreamFailure:
      // An upstream already threw  and we cancelled everything already.
      // We can just transition to finished now
      state = .finished

      return .none

    case .finished:
      // We are already finished so nothing to do here:
      state = .finished

      return .none

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `next()`.
  enum NextAction {
    /// Indicates that a new `Task` should be created that consumes the sequence and the downstream must be supsended
    case startTaskAndSuspendDownstreamTask(Base1, Base2, Base3?)
    /// Indicates that the `element` should be returned.
    case returnElement(Result<Element, Error>)
    /// Indicates that `nil` should be returned.
    case returnNil
    /// Indicates that the `error` should be thrown.
    case throwError(Error)
    /// Indicates that the downstream task should be suspended.
    case suspendDownstreamTask
  }

  mutating func next() -> NextAction {
    switch state {
    case .initial(let base1, let base2, let base3):
      // This is the first time we got demand signalled. We need to start the task now
      // We are transitioning to merging in the taskStarted method.
      return .startTaskAndSuspendDownstreamTask(base1, base2, base3)

    case .merging(_, _, _, _, .some):
      // We have multiple AsyncIterators iterating the sequence
      preconditionFailure("Internal inconsistency current state \(self.state) and received next()")

    case .merging(let task, var buffer, let upstreamContinuations, let upstreamsFinished, .none):
      state = .modifying

      guard let element = buffer.popFirst() else {
        // There was nothing in the buffer so we have to suspend the downstream task
        state = .merging(
          task: task,
          buffer: buffer,
          upstreamContinuations: upstreamContinuations,
          upstreamsFinished: upstreamsFinished,
          downstreamContinuation: nil
        )

        return .suspendDownstreamTask
      }
      // We have an element buffered already so we can just return that.
      state = .merging(
        task: task,
        buffer: buffer,
        upstreamContinuations: upstreamContinuations,
        upstreamsFinished: upstreamsFinished,
        downstreamContinuation: nil
      )

      return .returnElement(.success(element))

    case .upstreamFailure(var buffer, let error):
      state = .modifying

      guard let element = buffer.popFirst() else {
        // The buffer is empty and we can now throw the error
        // that an upstream produced
        state = .finished

        return .throwError(error)
      }
      // There was still a left over element that we need to return
      state = .upstreamFailure(
        buffer: buffer,
        error: error
      )

      return .returnElement(.success(element))

    case .finished:
      // We are already finished so we are just returning `nil`
      return .returnNil

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }

  /// Actions returned by `next(for)`.
  enum NextForAction {
    /// Indicates that the upstream continuations should be resumed to demand new elements.
    case resumeUpstreamContinuations(
      upstreamContinuations: [UnsafeContinuation<Void, Error>]
    )
  }

  mutating func next(for continuation: UnsafeContinuation<Element?, Error>) -> NextForAction {
    switch state {
    case .initial,
      .merging(_, _, _, _, .some),
      .upstreamFailure,
      .finished:
      // All other states are handled by `next` already so we should never get in here with
      // any of those
      preconditionFailure("Internal inconsistency current state \(self.state) and received next(for:)")

    case let .merging(task, buffer, upstreamContinuations, upstreamsFinished, .none):
      // We suspended the task and need signal the upstreams
      state = .merging(
        task: task,
        buffer: buffer,
        upstreamContinuations: [],  // TODO: don't alloc new array here
        upstreamsFinished: upstreamsFinished,
        downstreamContinuation: continuation
      )

      return .resumeUpstreamContinuations(
        upstreamContinuations: upstreamContinuations
      )

    case .modifying:
      preconditionFailure("Invalid state")
    }
  }
}

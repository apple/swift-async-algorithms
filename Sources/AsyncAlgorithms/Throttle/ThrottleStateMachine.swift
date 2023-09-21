//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct ThrottleStateMachine<Base: AsyncSequence, C: Clock, Reduced> {
  typealias Element = Reduced
  
  private enum State {
    /// The initial state before a call to `next` happened.
    case initial(base: Base)
    
    /// The state while we are waiting for downstream demand.
    case waitingForDemand(
      task: Task<Void, Never>,
      upstreamContinuation: UnsafeContinuation<Void, Error>?,
      bufferedElement: Element?
    )
    
    /// The state once the downstream signalled demand but before we received
    /// the first element from the upstream.
    case demandSignalled(
      task: Task<Void, Never>,
      downstreamContinuation: UnsafeContinuation<Result<Element?, Error>, Never>
    )
    
    /// The state while we are consuming the upstream and waiting for the Clock.sleep to finish.
    case throttling(
      task: Task<Void, Never>,
      upstreamContinuation: UnsafeContinuation<Void, Error>?,
      downstreamContinuation: UnsafeContinuation<Result<Element?, Error>, Never>,
      currentElement: Element
    )
    
    /// The state once any of the upstream sequences threw an `Error`.
    case upstreamFailure(
      error: Error
    )
    
    /// The state once all upstream sequences finished or the downstream consumer stopped, i.e. by dropping all references
    /// or by getting their `Task` cancelled.
    case finished
  }
  
  /// The state machine's current state.
  private var state: State
  /// The interval to debounce.
  private let interval: C.Instant.Duration
  /// The clock.
  private let clock: C
  
  init(base: Base, clock: C, interval: C.Instant.Duration) {
    self.state = .initial(base: base)
    self.clock = clock
    self.interval = interval
  }
  
  /// Actions returned by `iteratorDeinitialized()`.
  enum IteratorDeinitializedAction {
    /// Indicates that the `Task` needs to be cancelled and
    /// the upstream and clock continuation need to be resumed with a `CancellationError`.
    case cancelTaskAndUpstreamAndClockContinuations(
      task: Task<Void, Never>,
      upstreamContinuation: UnsafeContinuation<Void, Error>?
    )
  }
  
  mutating func iteratorDeinitialized() -> IteratorDeinitializedAction? {
    switch self.state {
    case .initial:
      // Nothing to do here. No demand was signalled until now
      return .none
      
    case .throttling, .demandSignalled:
      // An iterator was deinitialized while we have a suspended continuation.
      preconditionFailure("Internal inconsistency current state \(self.state) and received iteratorDeinitialized()")
      
    case .waitingForDemand(let task, let upstreamContinuation, _):
      // The iterator was dropped which signals that the consumer is finished.
      // We can transition to finished now and need to clean everything up.
      self.state = .finished
      
      return .cancelTaskAndUpstreamAndClockContinuations(
        task: task,
        upstreamContinuation: upstreamContinuation
      )
      
    case .upstreamFailure:
      // The iterator was dropped which signals that the consumer is finished.
      // We can transition to finished now. The cleanup already happened when we
      // transitioned to `upstreamFailure`.
      self.state = .finished
      
      return .none
      
    case .finished:
      // We are already finished so there is nothing left to clean up.
      // This is just the references dropping afterwards.
      return .none
    }
  }
  
  mutating func taskStarted(_ task: Task<Void, Never>, downstreamContinuation: UnsafeContinuation<Result<Element?, Error>, Never>) {
    switch self.state {
    case .initial:
      // The user called `next` and we are starting the `Task`
      // to consume the upstream sequence
      self.state = .demandSignalled(
        task: task,
        downstreamContinuation: downstreamContinuation
      )
      
    case .throttling, .demandSignalled, .waitingForDemand, .upstreamFailure, .finished:
      // We only a single iterator to be created so this must never happen.
      preconditionFailure("Internal inconsistency current state \(self.state) and received taskStarted()")
    }
  }
  
  /// Actions returned by `upstreamTaskSuspended()`.
  enum UpstreamTaskSuspendedAction {
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
  
  mutating func upstreamTaskSuspended(_ continuation: UnsafeContinuation<Void, Error>) -> UpstreamTaskSuspendedAction? {
    switch self.state {
    case .initial:
      // Child tasks are only created after we transitioned to `merging`
      preconditionFailure("Internal inconsistency current state \(self.state) and received childTaskSuspended()")
      
    case .waitingForDemand(_, .some, _), .throttling(_, .some, _, _):
      // We already have an upstream continuation so we can never get a second one
      preconditionFailure("Internal inconsistency current state \(self.state) and received childTaskSuspended()")
      
    case .upstreamFailure:
      // The upstream already failed so it should never suspend again since the child task
      // should have exited
      preconditionFailure("Internal inconsistency current state \(self.state) and received childTaskSuspended()")
      
    case .waitingForDemand(let task, .none, let bufferedElement):
      // The upstream task is ready to consume the next element
      // we are just waiting to get demand
      self.state = .waitingForDemand(
        task: task,
        upstreamContinuation: continuation,
        bufferedElement: bufferedElement
      )
      
      return .none
      
    case .demandSignalled:
      // It can happen that the demand got signalled before our upstream suspended for the first time
      // We need to resume it right away to demand the first element from the upstream
      return .resumeContinuation(upstreamContinuation: continuation)
      
    case .throttling(_, .none, _, _):
      // We are currently debouncing and the upstream task suspended again
      // We need to resume the continuation right away so that it continues to
      // consume new elements from the upstream
      
      return .resumeContinuation(upstreamContinuation: continuation)
      
    case .finished:
      // Since cancellation is cooperative it might be that child tasks are still getting
      // suspended even though we already cancelled them. We must tolerate this and just resume
      // the continuation with an error.
      return .resumeContinuationWithError(
        upstreamContinuation: continuation,
        error: CancellationError()
      )
    }
  }
  
  mutating func elementProduced(_ element: Element) {
    switch self.state {
    case .initial:
      // Child tasks that are producing elements are only created after we transitioned to `merging`
      preconditionFailure("Internal inconsistency current state \(self.state) and received elementProduced()")
      
    case .waitingForDemand(_, _, .some):
      // We can only ever buffer one element because of the race of both child tasks
      // After that element got buffered we are not resuming the upstream continuation
      // and should never get another element until we get downstream demand signalled
      preconditionFailure("Internal inconsistency current state \(self.state) and received elementProduced()")
      
    case .upstreamFailure:
      // The upstream already failed so it should never have produced another element
      preconditionFailure("Internal inconsistency current state \(self.state) and received childTaskSuspended()")
      
    case .waitingForDemand(let task, let upstreamContinuation, .none):
      // We got an element even though we don't have an outstanding demand
      // this can happen because we race the upstream and Clock child tasks
      // and the upstream might finish after the Clock. We just need
      // to buffer the element for the next demand.
      self.state = .waitingForDemand(
        task: task,
        upstreamContinuation: upstreamContinuation,
        bufferedElement: element
      )
      
    case .demandSignalled(let task, let downstreamContinuation):
      state = .waitingForDemand(task: task, upstreamContinuation: nil, bufferedElement: nil)
      downstreamContinuation.resume(returning: .success(element))
      
      
    case .throttling(let task, let upstreamContinuation, let downstreamContinuation, _):
      // We just got another element and the Clock hasn't finished sleeping yet
      // We just need to store the new element
      self.state = .throttling(
        task: task,
        upstreamContinuation: upstreamContinuation,
        downstreamContinuation: downstreamContinuation,
        currentElement: element
      )
      
    case .finished:
      // Since cancellation is cooperative it might be that child tasks
      // are still producing elements after we finished.
      // We are just going to drop them since there is nothing we can do
      break
    }
  }
  
  /// Actions returned by `upstreamFinished()`.
  enum UpstreamFinishedAction {
    /// Indicates that the task and the clock continuation should be cancelled.
    case cancelTask(
      task: Task<Void, Never>
    )
    /// Indicates that the downstream continuation should be resumed with `nil` and
    /// the task and the upstream continuation should be cancelled.
    case resumeContinuationWithNilAndCancelTaskAndUpstream(
      downstreamContinuation: UnsafeContinuation<Result<Element?, Error>, Never>,
      task: Task<Void, Never>,
      upstreamContinuation: UnsafeContinuation<Void, Error>?
    )
    /// Indicates that the downstream continuation should be resumed with `nil` and
    /// the task and the upstream continuation should be cancelled.
    case resumeContinuationWithElementAndCancelTaskAndUpstream(
      downstreamContinuation: UnsafeContinuation<Result<Element?, Error>, Never>,
      element: Element,
      task: Task<Void, Never>,
      upstreamContinuation: UnsafeContinuation<Void, Error>?
    )
  }
  
  mutating func upstreamFinished() -> UpstreamFinishedAction? {
    switch self.state {
    case .initial:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")
      
    case .waitingForDemand(_, .some, _):
      // We will never receive an upstream finished and have an outstanding continuation
      // since we only receive finish after resuming the upstream continuation
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")
      
    case .waitingForDemand(_, .none, .some):
      // We will never receive an upstream finished while we have a buffered element
      // To get there we would need to have received the buffered element and then
      // received upstream finished all while waiting for demand; however, we should have
      // never demanded the next element from upstream in the first place
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")
      
    case .upstreamFailure:
      // The upstream already failed so it should never have finished again
      preconditionFailure("Internal inconsistency current state \(self.state) and received childTaskSuspended()")
      
    case .waitingForDemand(let task, .none, .none):
      // We don't have any buffered element so we can just go ahead
      // and transition to finished and cancel everything
      self.state = .finished
      
      return .cancelTask(
        task: task
      )
      
    case .demandSignalled(let task, let downstreamContinuation):
      // We demanded the next element from the upstream after we got signalled demand
      // and the upstream finished. This means we need to resume the downstream with nil
      self.state = .finished
      
      return .resumeContinuationWithNilAndCancelTaskAndUpstream(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuation: nil
      )
      
    case .throttling(let task, let upstreamContinuation, let downstreamContinuation, let currentElement):
      // We are debouncing and the upstream finished. At this point
      // we can just resume the downstream continuation with element and cancel everything else
      self.state = .finished
      
      return .resumeContinuationWithElementAndCancelTaskAndUpstream(
        downstreamContinuation: downstreamContinuation,
        element: currentElement,
        task: task,
        upstreamContinuation: upstreamContinuation
      )
      
    case .finished:
      // This is just everything finishing up, nothing to do here
      return .none
    }
  }
  
  /// Actions returned by `upstreamThrew()`.
  enum UpstreamThrewAction {
    /// Indicates that the task and the clock continuation should be cancelled.
    case cancelTask(
      task: Task<Void, Never>
    )
    /// Indicates that the downstream continuation should be resumed with the `error` and
    /// the task and the upstream continuation should be cancelled.
    case resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuation(
      downstreamContinuation: UnsafeContinuation<Result<Element?, Error>, Never>,
      error: Error,
      task: Task<Void, Never>,
      upstreamContinuation: UnsafeContinuation<Void, Error>?
    )
  }
  
  mutating func upstreamThrew(_ error: Error) -> UpstreamThrewAction? {
    switch self.state {
    case .initial:
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamThrew()")
      
    case .waitingForDemand(_, .some, _):
      // We will never receive an upstream threw and have an outstanding continuation
      // since we only receive threw after resuming the upstream continuation
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")
      
    case .waitingForDemand(_, .none, .some):
      // We will never receive an upstream threw while we have a buffered element
      // To get there we would need to have received the buffered element and then
      // received upstream threw all while waiting for demand; however, we should have
      // never demanded the next element from upstream in the first place
      preconditionFailure("Internal inconsistency current state \(self.state) and received upstreamFinished()")
      
    case .upstreamFailure:
      // We need to tolerate multiple upstreams failing
      return .none
      
    case .waitingForDemand(let task, .none, .none):
      // We don't have any buffered element so we can just go ahead
      // and transition to finished and cancel everything
      self.state = .finished
      
      return .cancelTask(
        task: task
      )
      
    case .demandSignalled(let task, let downstreamContinuation):
      // We demanded the next element from the upstream after we got signalled demand
      // and the upstream threw. This means we need to resume the downstream with the error
      self.state = .finished
      
      return .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuation(
        downstreamContinuation: downstreamContinuation,
        error: error,
        task: task,
        upstreamContinuation: nil
      )
      
    case .throttling(let task, let upstreamContinuation, let downstreamContinuation, _):
      // We are debouncing and the upstream threw. At this point
      // we can just resume the downstream continuation with error and cancel everything else
      self.state = .finished
      
      return .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuation(
        downstreamContinuation: downstreamContinuation,
        error: error,
        task: task,
        upstreamContinuation: upstreamContinuation
      )
      
    case .finished:
      // This is just everything finishing up, nothing to do here
      return .none
    }
  }
  
  /// Actions returned by `cancelled()`.
  enum CancelledAction {
    /// Indicates that the downstream continuation needs to be resumed and
    /// task and the upstream continuations should be cancelled.
    case resumeDownstreamContinuationWithNilAndCancelTaskAndUpstream(
      downstreamContinuation: UnsafeContinuation<Result<Element?, Error>, Never>,
      task: Task<Void, Never>,
      upstreamContinuation: UnsafeContinuation<Void, Error>?
    )
  }
  
  mutating func cancelled() -> CancelledAction? {
    switch self.state {
    case .initial:
      state = .finished
      return .none
      
    case .waitingForDemand:
      // We got cancelled before we event got any demand. This can happen if a cancelled task
      // calls next and the onCancel handler runs first. We can transition to finished right away.
      self.state = .finished
      
      return .none
      
    case .demandSignalled(let task, let downstreamContinuation):
      // We got cancelled while we were waiting for the first upstream element
      // We can cancel everything at this point and return nil
      self.state = .finished
      
      return .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstream(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuation: nil
      )
      
    case .throttling(let task, let upstreamContinuation, let downstreamContinuation, _):
      // We got cancelled while debouncing.
      // We can cancel everything at this point and return nil
      self.state = .finished
      
      return .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstream(
        downstreamContinuation: downstreamContinuation,
        task: task,
        upstreamContinuation: upstreamContinuation
      )
      
    case .upstreamFailure:
      // An upstream already threw  and we cancelled everything already.
      // We should stay in the upstream failure state until the error is consumed
      return .none
      
    case .finished:
      // We are already finished so nothing to do here:
      self.state = .finished
      
      return .none
    }
  }
  
  /// Actions returned by `next()`.
  enum NextAction {
    /// Indicates that a new `Task` should be created that consumes the sequence.
    case startTask(Base)
    case resumeUpstreamContinuation(
      upstreamContinuation: UnsafeContinuation<Void, Error>?
    )
    /// Indicates that the downstream continuation should be resumed with `nil`.
    case resumeDownstreamContinuationWithNil(UnsafeContinuation<Result<Element?, Error>, Never>)
    /// Indicates that the downstream continuation should be resumed with the error.
    case resumeDownstreamContinuationWithError(
      UnsafeContinuation<Result<Element?, Error>, Never>,
      Error
    )
  }
  
  mutating func next(for continuation: UnsafeContinuation<Result<Element?, Error>, Never>) -> NextAction {
    switch self.state {
    case .initial(let base):
      // This is the first time we get demand singalled so we have to start the task
      // The transition to the next state is done in the taskStarted method
      return .startTask(base)
      
    case .demandSignalled, .throttling:
      // We already got demand signalled and have suspended the downstream task
      // Getting a second next calls means the iterator was transferred across Tasks which is not allowed
      preconditionFailure("Internal inconsistency current state \(self.state) and received next()")
      
    case .waitingForDemand(let task, let upstreamContinuation, let bufferedElement):
      if let bufferedElement = bufferedElement {
        // We already got an element from the last buffered one
        // We can kick of the clock and upstream consumption right away and transition to debouncing
        self.state = .throttling(
          task: task,
          upstreamContinuation: nil,
          downstreamContinuation: continuation,
          currentElement: bufferedElement
        )
        
        return .resumeUpstreamContinuation(
          upstreamContinuation: upstreamContinuation
        )
      } else {
        // We don't have a buffered element so have to resume the upstream continuation
        // to get the first one and transition to demandSignalled
        self.state = .demandSignalled(
          task: task,
          downstreamContinuation: continuation
        )
        
        return .resumeUpstreamContinuation(upstreamContinuation: upstreamContinuation)
      }
      
    case .upstreamFailure(let error):
      // The upstream threw and haven't delivered the error yet
      // Let's deliver it and transition to finished
      self.state = .finished
      
      return .resumeDownstreamContinuationWithError(continuation, error)
      
    case .finished:
      // We are already finished so we are just returning `nil`
      return .resumeDownstreamContinuationWithNil(continuation)
    }
  }
}

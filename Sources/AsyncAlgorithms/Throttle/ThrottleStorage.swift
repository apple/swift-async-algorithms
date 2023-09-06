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
final class ThrottleStorage<Base: AsyncSequence, C: Clock, Reduced>: @unchecked Sendable where Base: Sendable {
  typealias Element = Reduced
  
  /// The state machine protected with a lock.
  private let stateMachine: ManagedCriticalState<ThrottleStateMachine<Base, C, Reduced>>
  /// The interval to throttle.
  private let interval: C.Instant.Duration
  /// The clock.
  private let clock: C
  
  private let reducing: @Sendable (Reduced?, Base.Element) async -> Reduced
  
  init(_ base: Base, interval: C.Instant.Duration, clock: C, reducing: @Sendable @escaping (Reduced?, Base.Element) async -> Reduced) {
    self.stateMachine = .init(.init(base: base, clock: clock, interval: interval))
    self.interval = interval
    self.clock = clock
    self.reducing = reducing
  }
  
  func iteratorDeinitialized() {
    let action = self.stateMachine.withCriticalRegion { $0.iteratorDeinitialized() }
    
    switch action {
    case .cancelTaskAndUpstreamAndClockContinuations(
      let task,
      let upstreamContinuation
    ):
      upstreamContinuation?.resume(throwing: CancellationError())
      
      task.cancel()
      
    case .none:
      break
    }
  }
  
  func next() async rethrows -> Element? {
    // We need to handle cancellation here because we are creating a continuation
    // and because we need to cancel the `Task` we created to consume the upstream
    return try await withTaskCancellationHandler {
      // We always suspend since we can never return an element right away
      
      let result: Result<Element?, Error> = await withUnsafeContinuation { continuation in
        self.stateMachine.withCriticalRegion {
          let action = $0.next(for: continuation)
          
          switch action {
          case .startTask(let base):
            self.startTask(
              stateMachine: &$0,
              base: base,
              downstreamContinuation: continuation
            )
            
          case .resumeUpstreamContinuation(let upstreamContinuation):
            // This is signalling the upstream task that is consuming the upstream
            // sequence to signal demand.
            upstreamContinuation?.resume(returning: ())
          case .resumeDownstreamContinuationWithNil(let continuation):
            continuation.resume(returning: .success(nil))
            
          case .resumeDownstreamContinuationWithError(let continuation, let error):
            continuation.resume(returning: .failure(error))
          }
        }
      }
      
      return try result._rethrowGet()
    } onCancel: {
      let action = self.stateMachine.withCriticalRegion { $0.cancelled() }
      
      switch action {
      case .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstream(
        let downstreamContinuation,
        let task,
        let upstreamContinuation
      ):
        upstreamContinuation?.resume(throwing: CancellationError())
        
        task.cancel()
        
        downstreamContinuation.resume(returning: .success(nil))
        
      case .none:
        break
      }
    }
  }
  
  private func startTask(
    stateMachine: inout ThrottleStateMachine<Base, C, Reduced>,
    base: Base,
    downstreamContinuation: UnsafeContinuation<Result<Reduced?, Error>, Never>
  ) {
    let task = Task {
      var reduced: Reduced?
      var last: C.Instant?
      var iterator = base.makeAsyncIterator()
      
      do {
        // This is our upstream consumption loop
        loop: while true {
          // We are creating a continuation before requesting the next
          // element from upstream. This continuation is only resumed
          // if the downstream consumer called `next` to signal his demand
          // and until the Clock sleep finished.
          try await withUnsafeThrowingContinuation { continuation in
            let action = self.stateMachine.withCriticalRegion { $0.upstreamTaskSuspended(continuation) }
            
            switch action {
            case .resumeContinuation(let continuation):
              // This happens if there is outstanding demand
              // and we need to demand from upstream right away
              continuation.resume(returning: ())
              
            case .resumeContinuationWithError(let continuation, let error):
              // This happens if the task got cancelled.
              continuation.resume(throwing: error)
              
            case .none:
              break
            }
          }
          
          // We got signalled from the downstream that we have demand so let's
          // request a new element from the upstream
          if let item = try await iterator.next() {
            let element = await self.reducing(reduced, item)
            reduced = element
            let now = self.clock.now
            if let prev = last {
              let elapsed = prev.duration(to: now)
              // ensure the interval since the last emission is greater than or equal to the period of throttling
              if elapsed >= interval {
                last = now
                reduced = nil
                self.stateMachine.withCriticalRegion {
                  $0.elementProduced(element)
                }
              }
            } else {
              // nothing has previously been emitted so consider this not to be rate limited
              last = now
              reduced = nil
              self.stateMachine.withCriticalRegion {
                $0.elementProduced(element)
              }
            }
            
          } else {
            // The upstream returned `nil` which indicates that it finished
            let action = self.stateMachine.withCriticalRegion { $0.upstreamFinished() }
            
            // All of this is mostly cleanup around the Task and the outstanding
            // continuations used for signalling.
            switch action {
            case .cancelTask(let task):
              task.cancel()
              
              break loop
            case .resumeContinuationWithNilAndCancelTaskAndUpstream(
              let downstreamContinuation,
              let task,
              let upstreamContinuation
            ):
              upstreamContinuation?.resume(throwing: CancellationError())
              task.cancel()
              
              downstreamContinuation.resume(returning: .success(nil))
              
              break loop
              
            case .resumeContinuationWithElementAndCancelTaskAndUpstream(
              let downstreamContinuation,
              let element,
              let task,
              let upstreamContinuation
            ):
              upstreamContinuation?.resume(throwing: CancellationError())
              task.cancel()
              
              downstreamContinuation.resume(returning: .success(element))
              
              break loop
              
            case .none:
              
              break loop
            }
          }
        }
      } catch {
        self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.upstreamThrew(error)
          switch action {
          case .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuation(
            let downstreamContinuation,
            let error,
            let task,
            let upstreamContinuation
          ):
            upstreamContinuation?.resume(throwing: CancellationError())
            task.cancel()
            downstreamContinuation.resume(returning: .failure(error))
          case .cancelTask(
            let task
          ):
            task.cancel()
          case .none:
            break
          }
        }
      }
    }
    stateMachine.taskStarted(task, downstreamContinuation: downstreamContinuation)
  }
}

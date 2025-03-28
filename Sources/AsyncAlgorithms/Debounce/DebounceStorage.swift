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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class DebounceStorage<Base: AsyncSequence & Sendable, C: Clock>: Sendable where Base.Element: Sendable {
  typealias Element = Base.Element

  /// The state machine protected with a lock.
  private let stateMachine: ManagedCriticalState<DebounceStateMachine<Base, C>>
  /// The interval to debounce.
  private let interval: C.Instant.Duration
  /// The tolerance for the clock.
  private let tolerance: C.Instant.Duration?
  /// The clock.
  private let clock: C

  init(base: Base, interval: C.Instant.Duration, tolerance: C.Instant.Duration?, clock: C) {
    self.stateMachine = .init(.init(base: base, clock: clock, interval: interval))
    self.interval = interval
    self.tolerance = tolerance
    self.clock = clock
  }

  func iteratorDeinitialized() {
    let action = self.stateMachine.withCriticalRegion { $0.iteratorDeinitialized() }

    switch action {
    case .cancelTaskAndUpstreamAndClockContinuations(
      let task,
      let upstreamContinuation,
      let clockContinuation
    ):
      upstreamContinuation?.resume(throwing: CancellationError())
      clockContinuation?.resume(throwing: CancellationError())

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
        let action: DebounceStateMachine<Base, C>.NextAction? = self.stateMachine.withCriticalRegion {
          let action = $0.next(for: continuation)

          switch action {
          case .startTask(let base):
            self.startTask(
              stateMachine: &$0,
              base: base,
              downstreamContinuation: continuation
            )
            return nil

          case .resumeUpstreamContinuation:
            return action

          case .resumeUpstreamAndClockContinuation:
            return action

          case .resumeDownstreamContinuationWithNil:
            return action

          case .resumeDownstreamContinuationWithError:
            return action
          }
        }

        switch action {
        case .startTask:
          // We are handling the startTask in the lock already because we want to avoid
          // other inputs interleaving while starting the task
          fatalError("Internal inconsistency")

        case .resumeUpstreamContinuation(let upstreamContinuation):
          // This is signalling the upstream task that is consuming the upstream
          // sequence to signal demand.
          upstreamContinuation?.resume(returning: ())

        case .resumeUpstreamAndClockContinuation(let upstreamContinuation, let clockContinuation, let deadline):
          // This is signalling the upstream task that is consuming the upstream
          // sequence to signal demand and start the clock task.
          upstreamContinuation?.resume(returning: ())
          clockContinuation?.resume(returning: deadline)

        case .resumeDownstreamContinuationWithNil(let continuation):
          continuation.resume(returning: .success(nil))

        case .resumeDownstreamContinuationWithError(let continuation, let error):
          continuation.resume(returning: .failure(error))

        case .none:
          break
        }
      }

      return try result._rethrowGet()
    } onCancel: {
      let action = self.stateMachine.withCriticalRegion { $0.cancelled() }

      switch action {
      case .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamAndClockContinuation(
        let downstreamContinuation,
        let task,
        let upstreamContinuation,
        let clockContinuation
      ):
        upstreamContinuation?.resume(throwing: CancellationError())
        clockContinuation?.resume(throwing: CancellationError())

        task.cancel()

        downstreamContinuation.resume(returning: .success(nil))

      case .none:
        break
      }
    }
  }

  private func startTask(
    stateMachine: inout DebounceStateMachine<Base, C>,
    base: Base,
    downstreamContinuation: UnsafeContinuation<Result<Base.Element?, Error>, Never>
  ) {
    let task = Task {
      await withThrowingTaskGroup(of: Void.self) { group in
        // The task that consumes the upstream sequence
        group.addTask {
          var iterator = base.makeAsyncIterator()

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
            if let element = try await iterator.next() {
              let action = self.stateMachine.withCriticalRegion {
                let deadline = self.clock.now.advanced(by: self.interval)
                return $0.elementProduced(element, deadline: deadline)
              }

              switch action {
              case .resumeClockContinuation(let clockContinuation, let deadline):
                clockContinuation?.resume(returning: deadline)

              case .none:
                break
              }
            } else {
              // The upstream returned `nil` which indicates that it finished
              let action = self.stateMachine.withCriticalRegion { $0.upstreamFinished() }

              // All of this is mostly cleanup around the Task and the outstanding
              // continuations used for signalling.
              switch action {
              case .cancelTaskAndClockContinuation(let task, let clockContinuation):
                task.cancel()
                clockContinuation?.resume(throwing: CancellationError())

                break loop
              case .resumeContinuationWithNilAndCancelTaskAndUpstreamAndClockContinuation(
                let downstreamContinuation,
                let task,
                let upstreamContinuation,
                let clockContinuation
              ):
                upstreamContinuation?.resume(throwing: CancellationError())
                clockContinuation?.resume(throwing: CancellationError())
                task.cancel()

                downstreamContinuation.resume(returning: .success(nil))

                break loop

              case .resumeContinuationWithElementAndCancelTaskAndUpstreamAndClockContinuation(
                let downstreamContinuation,
                let element,
                let task,
                let upstreamContinuation,
                let clockContinuation
              ):
                upstreamContinuation?.resume(throwing: CancellationError())
                clockContinuation?.resume(throwing: CancellationError())
                task.cancel()

                downstreamContinuation.resume(returning: .success(element))

                break loop

              case .none:

                break loop
              }
            }
          }
        }

        group.addTask {
          // This is our clock scheduling loop
          loop: while true {
            do {
              // We are creating a continuation sleeping on the Clock.
              // This continuation is only resumed if the downstream consumer called `next`.
              let deadline: C.Instant = try await withUnsafeThrowingContinuation { continuation in
                let action = self.stateMachine.withCriticalRegion {
                  $0.clockTaskSuspended(continuation)
                }

                switch action {
                case .resumeContinuation(let continuation, let deadline):
                  // This happens if there is outstanding demand
                  // and we need to demand from upstream right away
                  continuation.resume(returning: deadline)

                case .resumeContinuationWithError(let continuation, let error):
                  // This happens if the task got cancelled.
                  continuation.resume(throwing: error)

                case .none:
                  break
                }
              }

              try await self.clock.sleep(until: deadline, tolerance: self.tolerance)

              let action = self.stateMachine.withCriticalRegion { $0.clockSleepFinished() }

              switch action {
              case .resumeDownstreamContinuation(let downstreamContinuation, let element):
                downstreamContinuation.resume(returning: .success(element))

              case .none:
                break
              }
            } catch {
              // The only error that we expect is the `CancellationError`
              // thrown from the Clock.sleep or from the withUnsafeContinuation.
              // This happens if we are cleaning everything up. We can just drop that error and break our loop
              precondition(
                error is CancellationError,
                "Received unexpected error \(error) in the Clock loop"
              )
              break loop
            }
          }
        }

        while !group.isEmpty {
          do {
            try await group.next()
          } catch {
            // One of the upstream sequences threw an error
            let action = self.stateMachine.withCriticalRegion { stateMachine in
              stateMachine.upstreamThrew(error)
            }

            switch action {
            case .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuation(
              let downstreamContinuation,
              let error,
              let task,
              let upstreamContinuation,
              let clockContinuation
            ):
              upstreamContinuation?.resume(throwing: CancellationError())
              clockContinuation?.resume(throwing: CancellationError())

              task.cancel()

              downstreamContinuation.resume(returning: .failure(error))

            case .cancelTaskAndClockContinuation(
              let task,
              let clockContinuation
            ):
              clockContinuation?.resume(throwing: CancellationError())
              task.cancel()
            case .none:
              break
            }
          }

          group.cancelAll()
        }
      }
    }

    stateMachine.taskStarted(task, downstreamContinuation: downstreamContinuation)
  }
}

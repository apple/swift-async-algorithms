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

@available(AsyncAlgorithms 1.0, *)
final class ZipStorage<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
where
  Base1: Sendable,
  Base1.Element: Sendable,
  Base2: Sendable,
  Base2.Element: Sendable,
  Base3: Sendable,
  Base3.Element: Sendable
{
  typealias StateMachine = ZipStateMachine<Base1, Base2, Base3>

  private let stateMachine: ManagedCriticalState<StateMachine>

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3?) {
    self.stateMachine = .init(.init(base1: base1, base2: base2, base3: base3))
  }

  func iteratorDeinitialized() {
    let action = self.stateMachine.withCriticalRegion { $0.iteratorDeinitialized() }

    switch action {
    case .cancelTaskAndUpstreamContinuations(
      let task,
      let upstreamContinuation
    ):
      upstreamContinuation.forEach { $0.resume(throwing: CancellationError()) }

      task.cancel()

    case .none:
      break
    }
  }

  func next() async rethrows -> (Base1.Element, Base2.Element, Base3.Element?)? {
    try await withTaskCancellationHandler {
      let result = await withUnsafeContinuation { continuation in
        let action: StateMachine.NextAction? = self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.next(for: continuation)
          switch action {
          case .startTask(let base1, let base2, let base3):
            // first iteration, we start one child task per base to iterate over them
            self.startTask(
              stateMachine: &stateMachine,
              base1: base1,
              base2: base2,
              base3: base3,
              downstreamContinuation: continuation
            )
            return nil

          case .resumeUpstreamContinuations:
            return action

          case .resumeDownstreamContinuationWithNil:
            return action
          }
        }

        switch action {
        case .startTask:
          // We are handling the startTask in the lock already because we want to avoid
          // other inputs interleaving while starting the task
          fatalError("Internal inconsistency")

        case .resumeUpstreamContinuations(let upstreamContinuations):
          // bases can be iterated over for 1 iteration so their next value can be retrieved
          upstreamContinuations.forEach { $0.resume() }

        case .resumeDownstreamContinuationWithNil(let continuation):
          // the async sequence is already finished, immediately resuming
          continuation.resume(returning: .success(nil))

        case .none:
          break
        }
      }

      return try result._rethrowGet()

    } onCancel: {
      let action = self.stateMachine.withCriticalRegion { stateMachine in
        stateMachine.cancelled()
      }

      switch action {
      case .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
        let downstreamContinuation,
        let task,
        let upstreamContinuations
      ):
        upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
        task.cancel()

        downstreamContinuation.resume(returning: .success(nil))

      case .cancelTaskAndUpstreamContinuations(let task, let upstreamContinuations):
        upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
        task.cancel()

      case .none:
        break
      }
    }
  }

  private func startTask(
    stateMachine: inout StateMachine,
    base1: Base1,
    base2: Base2,
    base3: Base3?,
    downstreamContinuation: StateMachine.DownstreamContinuation
  ) {
    // This creates a new `Task` that is iterating the upstream
    // sequences. We must store it to cancel it at the right times.
    let task = Task {
      await withThrowingTaskGroup(of: Void.self) { group in
        // For each upstream sequence we are adding a child task that
        // is consuming the upstream sequence
        group.addTask {
          var base1Iterator = base1.makeAsyncIterator()

          while true {
            // We are creating a continuation before requesting the next
            // element from upstream. This continuation is only resumed
            // if the downstream consumer called `next` to signal his demand.
            try await withUnsafeThrowingContinuation { continuation in
              let action = self.stateMachine.withCriticalRegion { stateMachine in
                stateMachine.childTaskSuspended(baseIndex: 0, continuation: continuation)
              }

              switch action {
              case .resumeContinuation(let upstreamContinuation):
                upstreamContinuation.resume()

              case .resumeContinuationWithError(let upstreamContinuation, let error):
                upstreamContinuation.resume(throwing: error)

              case .none:
                break
              }
            }

            if let element1 = try await base1Iterator.next() {
              let action = self.stateMachine.withCriticalRegion { stateMachine in
                stateMachine.elementProduced((element1, nil, nil))
              }

              switch action {
              case .resumeContinuation(let downstreamContinuation, let result):
                downstreamContinuation.resume(returning: result)

              case .none:
                break
              }
            } else {
              let action = self.stateMachine.withCriticalRegion { stateMachine in
                stateMachine.upstreamFinished()
              }

              switch action {
              case .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                let downstreamContinuation,
                let task,
                let upstreamContinuations
              ):

                upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                task.cancel()

                downstreamContinuation.resume(returning: .success(nil))

              case .none:
                break
              }
            }
          }
        }

        group.addTask {
          var base2Iterator = base2.makeAsyncIterator()

          while true {
            // We are creating a continuation before requesting the next
            // element from upstream. This continuation is only resumed
            // if the downstream consumer called `next` to signal his demand.
            try await withUnsafeThrowingContinuation { continuation in
              let action = self.stateMachine.withCriticalRegion { stateMachine in
                stateMachine.childTaskSuspended(baseIndex: 1, continuation: continuation)
              }

              switch action {
              case .resumeContinuation(let upstreamContinuation):
                upstreamContinuation.resume()

              case .resumeContinuationWithError(let upstreamContinuation, let error):
                upstreamContinuation.resume(throwing: error)

              case .none:
                break
              }
            }

            if let element2 = try await base2Iterator.next() {
              let action = self.stateMachine.withCriticalRegion { stateMachine in
                stateMachine.elementProduced((nil, element2, nil))
              }

              switch action {
              case .resumeContinuation(let downstreamContinuation, let result):
                downstreamContinuation.resume(returning: result)

              case .none:
                break
              }
            } else {
              let action = self.stateMachine.withCriticalRegion { stateMachine in
                stateMachine.upstreamFinished()
              }

              switch action {
              case .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                let downstreamContinuation,
                let task,
                let upstreamContinuations
              ):

                upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                task.cancel()

                downstreamContinuation.resume(returning: .success(nil))

              case .none:
                break
              }
            }
          }
        }

        if let base3 = base3 {
          group.addTask {
            var base3Iterator = base3.makeAsyncIterator()

            while true {
              // We are creating a continuation before requesting the next
              // element from upstream. This continuation is only resumed
              // if the downstream consumer called `next` to signal his demand.
              try await withUnsafeThrowingContinuation { continuation in
                let action = self.stateMachine.withCriticalRegion { stateMachine in
                  stateMachine.childTaskSuspended(baseIndex: 2, continuation: continuation)
                }

                switch action {
                case .resumeContinuation(let upstreamContinuation):
                  upstreamContinuation.resume()

                case .resumeContinuationWithError(let upstreamContinuation, let error):
                  upstreamContinuation.resume(throwing: error)

                case .none:
                  break
                }
              }

              if let element3 = try await base3Iterator.next() {
                let action = self.stateMachine.withCriticalRegion { stateMachine in
                  stateMachine.elementProduced((nil, nil, element3))
                }

                switch action {
                case .resumeContinuation(let downstreamContinuation, let result):
                  downstreamContinuation.resume(returning: result)

                case .none:
                  break
                }
              } else {
                let action = self.stateMachine.withCriticalRegion { stateMachine in
                  stateMachine.upstreamFinished()
                }

                switch action {
                case .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                  let downstreamContinuation,
                  let task,
                  let upstreamContinuations
                ):

                  upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                  task.cancel()

                  downstreamContinuation.resume(returning: .success(nil))

                case .none:
                  break
                }
              }
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
            case .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
              let downstreamContinuation,
              let error,
              let task,
              let upstreamContinuations
            ):
              upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
              task.cancel()

              downstreamContinuation.resume(returning: .failure(error))
            case .none:
              break
            }

            group.cancelAll()
          }
        }
      }
    }

    stateMachine.taskIsStarted(task: task, downstreamContinuation: downstreamContinuation)
  }
}

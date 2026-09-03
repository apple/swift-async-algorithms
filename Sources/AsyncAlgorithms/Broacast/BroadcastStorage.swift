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

final class BroadcastStorage<Base: AsyncSequence>: Sendable where Base: Sendable, Base.Element: Sendable {
  private let stateMachine: ManagedCriticalState<BroadcastStateMachine<Base>>
  private let ids: ManagedCriticalState<Int>

  init(base: Base) {
    self.stateMachine = ManagedCriticalState(BroadcastStateMachine(base: base))
    self.ids = ManagedCriticalState(0)
  }

  func generateId() -> Int {
    self.ids.withCriticalRegion { ids in
      ids += 1
      return ids
    }
  }

  func next(id: Int) async -> Result<Base.Element?, Error>? {
    let (shouldExit, element) = self.stateMachine.withCriticalRegion { stateMachine -> (Bool, Result<Base.Element?, Error>?) in
      let action = stateMachine.next(id: id)
      switch action {
        case .suspend:
          return (false, nil)
        case .exit(let element):
          return (true, element)
      }
    }

    if shouldExit {
      return element
    }

    return await withTaskCancellationHandler {
      await withUnsafeContinuation { (continuation: UnsafeContinuation<Result<Base.Element?, Error>, Never>) in
        self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.nextIsSuspended(
            id: id,
            continuation: continuation
          )
          switch action {
            case .startTask(let base):
              self.startTask(stateMachine: &stateMachine, base: base, id: id, downstreamContinuation: continuation)
            case .nextIsSuspendedAction(.resume(let element)):
              continuation.resume(returning: element)
            case .nextIsSuspendedAction(.suspend):
              break
            case .resumeProducerAndNextIsSuspendedAction(let upstreamContinuation, .resume(let element)):
              upstreamContinuation?.resume()
              continuation.resume(returning: element)
            case .resumeProducerAndNextIsSuspendedAction(let upstreamContinuation, .suspend):
              upstreamContinuation?.resume()
              break
          }
        }
      }
    } onCancel: {
      self.stateMachine.withCriticalRegion { stateMachine in
        let action = stateMachine.nextIsCancelled(id: id)
        switch action {
          case .nextIsCancelledAction(let continuation):
            continuation?.resume(returning: .success(nil))
        }
      }
    }
  }

  private func startTask(
    stateMachine: inout BroadcastStateMachine<Base>,
    base: Base,
    id: Int,
    downstreamContinuation: UnsafeContinuation<Result<Base.Element?, Error>, Never>
  ) {
    let task = Task {
      do {
        var iterator = base.makeAsyncIterator()
        loop: while true {
          await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            self.stateMachine.withCriticalRegion { stateMachine in
              let action = stateMachine.producerIsSuspended(
                continuation: continuation
              )

              switch action {
                case .resume:
                  continuation.resume()
                case .suspend:
                  break
              }
            }
          }

          guard let element = try await iterator.next() else {
            break loop
          }

          self.stateMachine.withCriticalRegion { stateMachine in
            let actions = stateMachine.element(element: element)
            for action in actions {
              switch action {
                case .none:
                  break
                case .resumeConsumer(let continuation):
                  continuation?.resume(returning: .success(element))
              }
            }
          }
        }

        self.stateMachine.withCriticalRegion { stateMachine in
          let actions = stateMachine.finish()
          for action in actions {
            switch action {
              case .none:
                break
              case .resumeConsumer(let continuation, _):
                continuation?.resume(returning: .success(nil))
            }
          }
        }
      } catch {
        self.stateMachine.withCriticalRegion { stateMachine in
          let actions = stateMachine.finish(error: error)
          for action in actions {
            switch action {
              case .none:
                break
              case .resumeConsumer(let continuation, _):
                continuation?.resume(returning: .failure(error))
            }
          }

        }
      }
    }

    let action = stateMachine.taskIsStarted(id: id, task: task, continuation: downstreamContinuation)

    switch action {
      case .suspend:
        break
      case .resume(let element):
        downstreamContinuation.resume(returning: element)
    }
  }

  deinit {
    let task = self.stateMachine.withCriticalRegion { $0.task() }
    task?.cancel()
  }
}

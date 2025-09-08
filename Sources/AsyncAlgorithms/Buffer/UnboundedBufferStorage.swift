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
final class UnboundedBufferStorage<Base: AsyncSequence>: Sendable where Base: Sendable {
  private let stateMachine: ManagedCriticalState<UnboundedBufferStateMachine<Base>>

  init(base: Base, policy: UnboundedBufferStateMachine<Base>.Policy) {
    self.stateMachine = ManagedCriticalState(UnboundedBufferStateMachine<Base>(base: base, policy: policy))
  }

  func next() async -> UnsafeTransfer<Result<Base.Element, Error>?> {
    return await withTaskCancellationHandler {

      let action: UnboundedBufferStateMachine<Base>.NextAction? = self.stateMachine.withCriticalRegion {
        stateMachine in
        let action = stateMachine.next()
        switch action {
        case .startTask(let base):
          self.startTask(stateMachine: &stateMachine, base: base)
          return nil
        case .suspend:
          return action
        case .returnResult:
          return action
        }
      }

      switch action {
      case .startTask:
        // We are handling the startTask in the lock already because we want to avoid
        // other inputs interleaving while starting the task
        fatalError("Internal inconsistency")
      case .suspend:
        break
      case .returnResult(let result):
        return UnsafeTransfer(result)
      case .none:
        break
      }

      return await withUnsafeContinuation {
        (continuation: UnsafeContinuation<UnsafeTransfer<Result<Base.Element, Error>?>, Never>) in
        let action = self.stateMachine.withCriticalRegion { stateMachine in
          stateMachine.nextSuspended(continuation: continuation)
        }
        switch action {
        case .none:
          break
        case .resumeConsumer(let result):
          continuation.resume(returning: UnsafeTransfer(result))
        }
      }
    } onCancel: {
      self.interrupted()
    }
  }

  private func startTask(
    stateMachine: inout UnboundedBufferStateMachine<Base>,
    base: Base
  ) {
    let task = Task {
      do {
        for try await element in base {
          let action = self.stateMachine.withCriticalRegion { stateMachine in
            stateMachine.elementProduced(element: element)
          }
          switch action {
          case .none:
            break
          case .resumeConsumer(let continuation, let result):
            continuation.resume(returning: result)
          }
        }

        let action = self.stateMachine.withCriticalRegion { stateMachine in
          stateMachine.finish(error: nil)
        }
        switch action {
        case .none:
          break
        case .resumeConsumer(let continuation):
          continuation?.resume(returning: UnsafeTransfer(nil))
        }
      } catch {
        let action = self.stateMachine.withCriticalRegion { stateMachine in
          stateMachine.finish(error: error)
        }
        switch action {
        case .none:
          break
        case .resumeConsumer(let continuation):
          continuation?.resume(returning: UnsafeTransfer(Result<Base.Element, Error>.failure(error)))
        }
      }
    }

    stateMachine.taskStarted(task: task)
  }

  func interrupted() {
    let action = self.stateMachine.withCriticalRegion { stateMachine in
      stateMachine.interrupted()
    }
    switch action {
    case .none:
      break
    case .resumeConsumer(let task, let continuation):
      task.cancel()
      continuation?.resume(returning: UnsafeTransfer(nil))
    }
  }

  deinit {
    self.interrupted()
  }
}

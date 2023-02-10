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

final class UnboundedBufferStorage<Base: AsyncSequence>: Sendable where Base: Sendable {
  private let stateMachine: ManagedCriticalState<UnboundedBufferStateMachine<Base>>

  init(base: Base, policy: UnboundedBufferStateMachine<Base>.Policy) {
    self.stateMachine = ManagedCriticalState(UnboundedBufferStateMachine<Base>(base: base, policy: policy))
  }

  func next() async -> Result<Base.Element, Error>? {
    return await withTaskCancellationHandler {

      let (shouldSuspend, result) = self.stateMachine.withCriticalRegion { stateMachine -> (Bool, Result<Base.Element, Error>?) in
        let action = stateMachine.next()
        switch action {
          case .startTask(let base):
            self.startTask(stateMachine: &stateMachine, base: base)
            return (true, nil)
          case .suspend:
            return (true, nil)
          case .returnResult(let result):
            return (false, result)
        }
      }

      if !shouldSuspend {
        return result
      }

      return await withUnsafeContinuation { (continuation: UnsafeContinuation<Result<Base.Element, Error>?, Never>) in
        self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.nextSuspended(continuation: continuation)
          switch action {
            case .none:
              break
            case .resumeConsumer(let result):
              continuation.resume(returning: result)
          }
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
          self.stateMachine.withCriticalRegion { stateMachine in
            let action = stateMachine.elementProduced(element: element)
            switch action {
              case .none:
                break
              case .resumeConsumer(let continuation, let result):
                continuation.resume(returning: result)
            }
          }
        }

        self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.finish(error: nil)
          switch action {
            case .none:
              break
            case .resumeConsumer(let continuation):
              continuation?.resume(returning: nil)
          }
        }
      } catch {
        self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.finish(error: error)
          switch action {
            case .none:
              break
            case .resumeConsumer(let continuation):
              continuation?.resume(returning: .failure(error))
          }
        }
      }
    }

    stateMachine.taskStarted(task: task)
  }

  func interrupted() {
    self.stateMachine.withCriticalRegion { stateMachine in
      let action = stateMachine.interrupted()
      switch action {
        case .none:
          break
        case .resumeConsumer(let task, let continuation):
          task.cancel()
          continuation?.resume(returning: nil)
      }
    }
  }

  deinit {
    self.interrupted()
  }
}

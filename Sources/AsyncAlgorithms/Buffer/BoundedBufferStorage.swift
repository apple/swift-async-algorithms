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

final class BoundedBufferStorage<Base: AsyncSequence>: Sendable where Base: Sendable {
  private let stateMachine: ManagedCriticalState<BoundedBufferStateMachine<Base>>

  init(base: Base, limit: Int) {
    self.stateMachine = ManagedCriticalState(BoundedBufferStateMachine(base: base, limit: limit))
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
          case .returnResult(let producerContinuation, let result):
            producerContinuation?.resume()
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
            case .returnResult(let producerContinuation, let result):
              producerContinuation?.resume()
              continuation.resume(returning: result)
          }
        }
      }
    } onCancel: {
      self.interrupted()
    }
  }

  private func startTask(
    stateMachine: inout BoundedBufferStateMachine<Base>,
    base: Base
  ) {
    let task = Task {
      do {
        var iterator = base.makeAsyncIterator()

        loop: while true {
          let shouldSuspend = self.stateMachine.withCriticalRegion { stateMachine -> Bool in
            return stateMachine.shouldSuspendProducer()
          }

          if shouldSuspend {
            await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
              self.stateMachine.withCriticalRegion { stateMachine in
                let action = stateMachine.producerSuspended(continuation: continuation)

                switch action {
                  case .none:
                    break
                  case .resumeProducer:
                    continuation.resume()
                }
              }
            }
          }

          guard let element = try await iterator.next() else {
            // the upstream is finished
            break loop
          }

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
        case .resumeProducerAndConsumer(let task, let producerContinuation, let consumerContinuation):
          task.cancel()
          producerContinuation?.resume()
          consumerContinuation?.resume(returning: nil)
      }
    }
  }

  deinit {
    self.interrupted()
  }
}

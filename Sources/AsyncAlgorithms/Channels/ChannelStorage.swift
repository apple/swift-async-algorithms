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
struct ChannelStorage<Element: Sendable, Failure: Error>: Sendable {
  private let stateMachine: ManagedCriticalState<ChannelStateMachine<Element, Failure>>
  private let ids = ManagedCriticalState<UInt64>(0)

  init() {
    self.stateMachine = ManagedCriticalState(ChannelStateMachine())
  }

  func generateId() -> UInt64 {
    self.ids.withCriticalRegion { ids in
      defer { ids &+= 1 }
      return ids
    }
  }

  func send(element: Element) async {
    // check if a suspension is needed
    let shouldExit = self.stateMachine.withCriticalRegion { stateMachine -> Bool in
      let action = stateMachine.send()

      switch action {
        case .suspend:
          // the element has not been delivered because no consumer available, we must suspend
          return false
        case .resumeConsumer(let continuation):
          continuation?.resume(returning: element)
          return true
      }
    }

    if shouldExit {
      return
    }

    let producerID = self.generateId()

    await withTaskCancellationHandler {
      // a suspension is needed
      await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
        self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.sendSuspended(continuation: continuation, element: element, producerID: producerID)

          switch action {
            case .none:
              break
            case .resumeProducer:
              continuation.resume()
            case .resumeProducerAndConsumer(let consumerContinuation):
              continuation.resume()
              consumerContinuation?.resume(returning: element)
          }
        }
      }
    } onCancel: {
      self.stateMachine.withCriticalRegion { stateMachine in
        let action = stateMachine.sendCancelled(producerID: producerID)

        switch action {
          case .none:
            break
          case .resumeProducer(let continuation):
            continuation?.resume()
        }
      }
    }
  }

  func finish(error: Failure? = nil) {
    self.stateMachine.withCriticalRegion { stateMachine in
      let action = stateMachine.finish(error: error)

      switch action {
        case .none:
          break
        case .resumeProducersAndConsumers(let producerContinuations, let consumerContinuations):
          producerContinuations.forEach { $0?.resume() }
          if let error {
            consumerContinuations.forEach { $0?.resume(throwing: error) }
          } else {
            consumerContinuations.forEach { $0?.resume(returning: nil) }
          }
      }
    }
  }

  func next() async throws -> Element? {
    let (shouldExit, result) = self.stateMachine.withCriticalRegion { stateMachine -> (Bool, Result<Element?, Error>?) in
      let action = stateMachine.next()

      switch action {
        case .suspend:
          return (false, nil)
        case .resumeProducer(let producerContinuation, let result):
          producerContinuation?.resume()
          return (true, result)
      }
    }

    if shouldExit {
      return try result?._rethrowGet()
    }

    let consumerID = self.generateId()

    return try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Element?, any Error>) in
        self.stateMachine.withCriticalRegion { stateMachine in
          let action = stateMachine.nextSuspended(
            continuation: continuation,
            consumerID: consumerID
          )

          switch action {
            case .none:
              break
            case .resumeConsumer(let element):
              continuation.resume(returning: element)
            case .resumeConsumerWithError(let error):
              continuation.resume(throwing: error)
            case .resumeProducerAndConsumer(let producerContinuation, let element):
              producerContinuation?.resume()
              continuation.resume(returning: element)
          }
        }
      }
    } onCancel: {
      self.stateMachine.withCriticalRegion { stateMachine in
        let action = stateMachine.nextCancelled(consumerID: consumerID)

        switch action {
          case .none:
            break
          case .resumeConsumer(let continuation):
            continuation?.resume(returning: nil)
        }
      }
    }
  }
}

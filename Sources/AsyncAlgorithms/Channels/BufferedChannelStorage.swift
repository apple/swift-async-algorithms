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

final class BufferedChannelStorage<Element> {
  private let stateMachine: ManagedCriticalState<BufferedChannelStateMachine<Element>>
  private let ids = ManagedCriticalState<Int>(0)

  #if DEBUG
  var onSendSuspended: (() -> Void)?
  var onNextSuspended: (() -> Void)?
  #endif

  init(bufferSize: UInt) {
    self.stateMachine = ManagedCriticalState(BufferedChannelStateMachine(bufferSize: bufferSize))
  }

  func generateId() -> Int {
    self.ids.withCriticalRegion { ids in
      defer { ids += 1 }
      return ids
    }
  }

  func send(element: Element) async {
    let shouldEarlyReturn = self.stateMachine.withCriticalRegion { stateMachine in
      let action = stateMachine.newElementFromProducer(element: element)

      switch action {
        case .earlyReturn:
          return true
        case .resumeConsumer(let continuation):
          continuation?.resume(returning: element)
          return true
        case .suspend:
          return false
      }
    }

    if shouldEarlyReturn {
      return
    }

    let producerId = self.generateId()
    let isCancelled = ManagedCriticalState(false)

    await withTaskCancellationHandler {
      await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
        self.stateMachine.withCriticalRegion { stateMachine in
          let isCancelled = isCancelled.withCriticalRegion { $0 }
          guard !isCancelled else { return }

          let action = stateMachine.producerHasSuspended(continuation: continuation, element: element, producerId: producerId)

          switch action {
            case .none:
              #if DEBUG
              self.onSendSuspended?()
              #endif
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
        isCancelled.withCriticalRegion { $0 = true }
        let action = stateMachine.producerHasBeenCancelled(producerId: producerId)

        switch action {
          case .none:
            break
          case .resumeProducer(let continuation):
            continuation?.resume()
        }
      }
    }
  }

  func finish() {
    self.stateMachine.withCriticalRegion { stateMachine in
      let action = stateMachine.channelHasFinished()

      switch action {
        case .none:
          break
        case .resumeConsumers(let continuations):
          continuations.forEach { $0?.resume(returning: nil) }
      }
    }
  }

  func next() async -> Element? {
    guard !Task.isCancelled else { return nil }

    let (shouldEarlyReturn, earlyElement) = self.stateMachine.withCriticalRegion { stateMachine in
      let action = stateMachine.newRequestFromConsumer()

      switch action {
        case .earlyReturn(let element):
          return (true, element)
        case .suspend:
          return (false, nil)
        case .resumeProducerAndEarlyReturn(let continuation, let element):
          continuation?.resume()
          return (true, element)
      }
    }

    if shouldEarlyReturn {
      return earlyElement
    }

    let consumerId = self.generateId()
    let isCancelled = ManagedCriticalState(false)

    return await withTaskCancellationHandler {
      return await withUnsafeContinuation { (continuation: UnsafeContinuation<Element?, Never>) in
        self.stateMachine.withCriticalRegion { stateMachine in
          let isCancelled = isCancelled.withCriticalRegion { $0 }
          guard !isCancelled else { return }

          let action = stateMachine.consumerHasSuspended(continuation: continuation, consumerId: consumerId)

          switch action {
            case .none:
              #if DEBUG
              self.onNextSuspended?()
              #endif
              break
            case .resumeConsumer(let element):
              continuation.resume(returning: element)
            case .resumeProducerAndConsumer(let producerContinuation, let element):
              producerContinuation?.resume()
              continuation.resume(returning: element)
          }
        }
      }
    } onCancel: {
      self.stateMachine.withCriticalRegion { stateMachine in
        isCancelled.withCriticalRegion { $0 = true }
        let action = stateMachine.consumerHasBeenCancelled(consumerId: consumerId)

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

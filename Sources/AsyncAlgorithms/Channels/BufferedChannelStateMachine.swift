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

import DequeModule
import OrderedCollections

struct BufferedChannelStateMachine<Element> {
  private struct SuspendedProducer: Hashable {
    let id: Int
    let continuation: UnsafeContinuation<Void, Never>?
    let element: Element?

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.id)
    }

    static func == (_ lhs: SuspendedProducer, _ rhs: SuspendedProducer) -> Bool {
      return lhs.id == rhs.id
    }

    static func placeHolder(id: Int) -> SuspendedProducer {
      SuspendedProducer(id: id, continuation: nil, element: nil)
    }
  }

  private struct SuspendedConsumer: Hashable {
    let id: Int
    let continuation: UnsafeContinuation<Element?, Never>?

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.id)
    }

    static func == (_ lhs: SuspendedConsumer, _ rhs: SuspendedConsumer) -> Bool {
      return lhs.id == rhs.id
    }

    static func placeHolder(id: Int) -> SuspendedConsumer {
      SuspendedConsumer(id: id, continuation: nil)
    }
  }

  private enum State {
    case idle
    case buffering(buffer: Deque<Element>)
    case waitingForConsumer(suspendedProducers: OrderedSet<SuspendedProducer>, buffer: Deque<Element>)
    case waitingForProducer(suspendedConsumers: OrderedSet<SuspendedConsumer>)
    case finished(suspendedProducers: OrderedSet<SuspendedProducer>?, buffer: Deque<Element>?)
    case modifying
  }

  private var state: State
  private let bufferSize: UInt

  init(bufferSize: UInt) {
    self.state = .idle
    self.bufferSize = bufferSize
  }

  enum NewElementFromProducerAction {
    case earlyReturn
    case suspend
    case resumeConsumer(continuation: UnsafeContinuation<Element?, Never>?)
  }

  mutating func newElementFromProducer(element: Element) -> NewElementFromProducerAction {
    switch self.state {
      case .idle:
        var buffer = Deque<Element>(minimumCapacity: Int(self.bufferSize))
        buffer.append(element)
        self.state = .buffering(buffer: buffer)
        return .earlyReturn
        
      case .buffering(var buffer):
        if buffer.count < self.bufferSize {
          // there are available slots in the buffer
          self.state = .modifying
          buffer.append(element)
          self.state = .buffering(buffer: buffer)
          return .earlyReturn
        } else {
          // the buffer is full, producers have to suspend
          return .suspend
        }

      case .waitingForConsumer:
        // the buffer is full, producers have to suspend
        return .suspend

      case .waitingForProducer(var suspendedConsumers):
        precondition(!suspendedConsumers.isEmpty, "Invalid state.")
        self.state = .modifying
        let suspendedConsumer = suspendedConsumers.removeFirst()
        if suspendedConsumers.isEmpty {
          self.state = .idle
        } else {
          self.state = .waitingForProducer(suspendedConsumers: suspendedConsumers)
        }
        return .resumeConsumer(continuation: suspendedConsumer.continuation)

      case .modifying:
        preconditionFailure("Invalid state.")

      case .finished:
        return .earlyReturn
    }
  }

  enum ProducerHasSuspendedAction {
    case none
    case resumeProducer
    case resumeProducerAndConsumer(continuation: UnsafeContinuation<Element?, Never>?)
  }

  mutating func producerHasSuspended(
    continuation: UnsafeContinuation<Void, Never>,
    element: Element,
    producerId: Int
  ) -> ProducerHasSuspendedAction {
    switch self.state {
      case .idle:
        var buffer = Deque<Element>(minimumCapacity: Int(self.bufferSize))
        buffer.append(element)
        self.state = .buffering(buffer: buffer)
        return .resumeProducer

      case .buffering(var buffer):
        if buffer.count < self.bufferSize {
          // there are available slots in the buffer
          self.state = .modifying
          buffer.append(element)
          self.state = .buffering(buffer: buffer)
          return .resumeProducer
        } else {
          // the buffer is full, the suspension is confirmed
          var suspendedProducers = OrderedSet<SuspendedProducer>()
          suspendedProducers.append(SuspendedProducer(id: producerId, continuation: continuation, element: element))
          self.state = .waitingForConsumer(suspendedProducers: suspendedProducers, buffer: buffer)
          return .none
        }

      case .waitingForConsumer(var suspendedProducers, let buffer):
        self.state = .modifying
        suspendedProducers.append(SuspendedProducer(id: producerId, continuation: continuation, element: element))
        self.state = .waitingForConsumer(suspendedProducers: suspendedProducers, buffer: buffer)
        return .none

      case .waitingForProducer(var suspendedConsumers):
        precondition(!suspendedConsumers.isEmpty, "Invalid state.")
        self.state = .modifying
        let suspendedConsumer = suspendedConsumers.removeFirst()
        if suspendedConsumers.isEmpty {
          self.state = .idle
        } else {
          self.state = .waitingForProducer(suspendedConsumers: suspendedConsumers)
        }
        return .resumeProducerAndConsumer(continuation: suspendedConsumer.continuation)

      case .modifying:
        preconditionFailure("Invalid state.")

      case .finished:
        return .resumeProducer
    }
  }

  enum ChannelHasFinishedAction {
    case none
    case resumeConsumers(continuations: any Collection<UnsafeContinuation<Element?, Never>?>)
  }

  mutating func channelHasFinished() -> ChannelHasFinishedAction {
    switch self.state {
      case .idle:
        self.state = .finished(suspendedProducers: nil, buffer: nil)
        return .none

      case .buffering(let buffer):
        self.state = .finished(suspendedProducers: nil, buffer: buffer)
        return .none

      case .waitingForConsumer(let suspendedProducers, let buffer):
        self.state = .finished(suspendedProducers: suspendedProducers, buffer: buffer)
        return .none

      case .waitingForProducer(let consumerContinuations):
        self.state = .finished(suspendedProducers: nil, buffer: nil)
        return .resumeConsumers(continuations: consumerContinuations.map { $0.continuation })

      case .modifying:
        preconditionFailure("Invalid state.")

      case .finished:
        return .none
    }
  }

  enum ProducerHasBeenCancelledAction {
    case none
    case resumeProducer(continuation: UnsafeContinuation<Void, Never>?)
  }

  mutating func producerHasBeenCancelled(producerId: Int) -> ProducerHasBeenCancelledAction {
    switch self.state {
      case .idle:
        return .none

      case .buffering:
        return .none

      case .waitingForConsumer(var suspendedProducers, let buffer):
        let placeHolder = SuspendedProducer.placeHolder(id: producerId)
        self.state = .modifying

        let removed = suspendedProducers.remove(placeHolder)
        if suspendedProducers.isEmpty {
          self.state = .buffering(buffer: buffer)
        } else {
          self.state = .waitingForConsumer(suspendedProducers: suspendedProducers, buffer: buffer)
        }

        if let removed {
          return .resumeProducer(continuation: removed.continuation)
        }
        return .none

      case .waitingForProducer:
        return .none

      case .modifying:
        preconditionFailure("Invalid state.")

      case .finished(var suspendedProducers, let buffer):
        let placeHolder = SuspendedProducer.placeHolder(id: producerId)
        self.state = .modifying

        let removed = suspendedProducers?.remove(placeHolder)
        self.state = .finished(suspendedProducers: suspendedProducers, buffer: buffer)

        if let removed {
          return .resumeProducer(continuation: removed.continuation)
        }
        return .none
    }
  }

  enum NewRequestFromConsumerAction {
    case suspend
    case earlyReturn(Element?)
    case resumeProducerAndEarlyReturn(UnsafeContinuation<Void, Never>?, Element)
  }

  mutating func newRequestFromConsumer() -> NewRequestFromConsumerAction {
    switch self.state {
      case .idle:
        // the buffer is empty, the consumer must suspend until an element is available
        return .suspend

      case .buffering(var buffer):
        precondition(!buffer.isEmpty, "Invalid state.")
        self.state = .modifying
        let element = buffer.popFirst()!
        if buffer.isEmpty {
          self.state = .idle
        } else {
          self.state = .buffering(buffer: buffer)
        }
        return .earlyReturn(element)

      case .waitingForConsumer(var suspendedProducers, var buffer):
        precondition(!buffer.isEmpty, "Invalid state.")
        precondition(!suspendedProducers.isEmpty, "Invalid state.")
        self.state = .modifying
        let element = buffer.popFirst()!
        let suspendedProducer = suspendedProducers.removeFirst()
        buffer.append(suspendedProducer.element!)
        if suspendedProducers.isEmpty {
          self.state = .buffering(buffer: buffer)
        } else {
          self.state = .waitingForConsumer(suspendedProducers: suspendedProducers, buffer: buffer)
        }
        return .resumeProducerAndEarlyReturn(suspendedProducer.continuation, element)

      case .waitingForProducer:
        // we are already waiting for producers, the consumer must suspend until an element is available
        return .suspend

      case .modifying:
        preconditionFailure("Invalid state.")

      case .finished(let suspendedProducers, var buffer):
        if suspendedProducers == nil && buffer == nil {
          // no more elements to dequeue
          return .earlyReturn(nil)
        }
        self.state = .modifying

        guard let element = buffer?.popFirst() else {
          // no more elements to dequeue from the buffer (implying no suspended sendings also)
          self.state = .finished(suspendedProducers: nil, buffer: nil)
          return .earlyReturn(nil)
        }

        // still at least an element in the buffer
        if var suspendedProducers, !suspendedProducers.isEmpty {
          // still some suspended producers, we can resume the first one and put the element in the buffer
          let suspendedProducer = suspendedProducers.removeFirst()
          buffer?.append(suspendedProducer.element!)
          self.state = .finished(suspendedProducers: suspendedProducers, buffer: buffer)
          return .resumeProducerAndEarlyReturn(suspendedProducer.continuation, element)
        }

        self.state = .finished(suspendedProducers: nil, buffer: buffer)
        return .resumeProducerAndEarlyReturn(nil, element)
    }
  }

  enum ConsumerHasSuspendedAction {
    case none
    case resumeConsumer(Element?)
    case resumeProducerAndConsumer(UnsafeContinuation<Void, Never>?, Element)
  }

  mutating func consumerHasSuspended(continuation: UnsafeContinuation<Element?, Never>, consumerId: Int) -> ConsumerHasSuspendedAction {
    switch self.state {
      case .idle:
        var suspendedConsumers = OrderedSet<SuspendedConsumer>()
        suspendedConsumers.append(SuspendedConsumer(id: consumerId, continuation: continuation))
        self.state = .waitingForProducer(suspendedConsumers: suspendedConsumers)
        return .none

      case .buffering(var buffer):
        precondition(!buffer.isEmpty, "Invalid state.")
        self.state = .modifying
        let element = buffer.popFirst()!
        if buffer.isEmpty {
          self.state = .idle
        } else {
          self.state = .buffering(buffer: buffer)
        }
        return .resumeConsumer(element)

      case .waitingForConsumer(var suspendedProducers, var buffer):
        precondition(!buffer.isEmpty, "Invalid state.")
        precondition(!suspendedProducers.isEmpty, "Invalid state.")
        self.state = .modifying
        let element = buffer.popFirst()!
        let suspendedProducer = suspendedProducers.removeFirst()
        buffer.append(suspendedProducer.element!)
        if suspendedProducers.isEmpty {
          self.state = .buffering(buffer: buffer)
        } else {
          self.state = .waitingForConsumer(suspendedProducers: suspendedProducers, buffer: buffer)
        }
        return .resumeProducerAndConsumer(suspendedProducer.continuation, element)

      case .waitingForProducer(var suspendedConsumers):
        self.state = .modifying
        suspendedConsumers.append(SuspendedConsumer(id: consumerId, continuation: continuation))
        self.state = .waitingForProducer(suspendedConsumers: suspendedConsumers)
        return .none

      case .modifying:
        preconditionFailure("Invalid state.")

      case .finished(var suspendedProducers, var buffer):
        if suspendedProducers == nil && buffer == nil {
          // no more elements to dequeue
          return .resumeConsumer(nil)
        }
        self.state = .modifying
        if let element = buffer?.popFirst() {
          if let suspendedProducer = suspendedProducers?.removeFirst() {
            buffer?.append(suspendedProducer.element!)
            return .resumeProducerAndConsumer(suspendedProducer.continuation, element)
          }
          return .resumeProducerAndConsumer(nil, element)
        } else {
          // no more elements to dequeue
          self.state = .finished(suspendedProducers: nil, buffer: nil)
          return .resumeConsumer(nil)
        }
    }
  }

  enum ConsumerHasBeenCancelledAction {
    case none
    case resumeConsumer(continuation: UnsafeContinuation<Element?, Never>?)
  }

  mutating func consumerHasBeenCancelled(consumerId: Int) -> ConsumerHasBeenCancelledAction {
    switch self.state {
      case .idle:
        return .none

      case .buffering:
        return .none

      case .waitingForConsumer:
        return .none

      case .waitingForProducer(var suspendedConsumers):
        let placeHolder = SuspendedConsumer.placeHolder(id: consumerId)
        self.state = .modifying

        let removed = suspendedConsumers.remove(placeHolder)
        if suspendedConsumers.isEmpty {
          self.state = .idle
        } else {
          self.state = .waitingForProducer(suspendedConsumers: suspendedConsumers)
        }

        if let removed {
          return .resumeConsumer(continuation: removed.continuation)
        }
        return .none

      case .modifying:
        preconditionFailure("Invalid state.")

      case .finished:
        return .none
    }
  }
}

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

struct BroadcastStateMachine<Base: AsyncSequence>: Sendable
where Base: Sendable, Base.Element: Sendable {
  typealias Channel = UnicastStateMachine<Base.Element>

  enum State {
    case initial(base: Base, channels: [Int: Channel])
    case broadcasting(
      task: Task<Void, Never>,
      suspendedProducer: UnsafeContinuation<Void, Never>?,
      channels: [Int: Channel],
      isBusy: Bool,
      demands: Set<Int>
    )
    case finished(channels: [Int: Channel])
  }

  private var state: State

  init(base: Base) {
    self.state = .initial(base: base, channels: [:])
  }

  func task() -> Task<Void, Never>? {
    switch self.state {
      case .broadcasting(let task, _, _, _, _):
        return task
      default:
        return nil
    }
  }

  mutating func taskIsStarted(
    id: Int,
    task: Task<Void, Never>,
    continuation: UnsafeContinuation<Result<Base.Element?, Error>, Never>
  ) -> Channel.NextIsSuspendedAction {
    switch self.state {
      case .initial(_, var channels):
        precondition(channels[id] != nil, "Invalid state.")
        var channel = channels[id]!
        let action = channel.nextIsSuspended(continuation: continuation)
        channels[id] = channel

        self.state = .broadcasting(task: task, suspendedProducer: nil, channels: channels, isBusy: true, demands: [id])
        return action
      case .broadcasting:
        preconditionFailure("Invalid state.")
      case .finished:
        preconditionFailure("Invalid state.")
    }
  }

  enum ProducerIsSuspendedAction {
    case resume
    case suspend
  }

  mutating func producerIsSuspended(
    continuation: UnsafeContinuation<Void, Never>
  ) -> ProducerIsSuspendedAction {
    switch self.state {
      case .initial:
        preconditionFailure("Invalid state.")
      case .broadcasting(let task, let suspendedProducer, let channels, _, var demands):
        precondition(suspendedProducer == nil, "Invalid state.")

        if !demands.isEmpty {
          demands.removeAll()
          self.state = .broadcasting(task: task, suspendedProducer: continuation, channels: channels, isBusy: true, demands: demands)
          return .resume
        }

        self.state = .broadcasting(task: task, suspendedProducer: continuation, channels: channels, isBusy: false, demands: demands)
        return .suspend
      case .finished:
        preconditionFailure("Invalid state.")
    }
  }

  mutating func element(element: Base.Element) -> [Channel.SendAction] {
    switch state {
      case .initial:
        preconditionFailure("Invalid state.")
      case .broadcasting(let task, _, var channels, _, let demands):
        var actions = [Channel.SendAction]()
        for entry in channels {
          let id = entry.key
          var channel = entry.value
          actions.append(channel.send(element))
          channels[id] = channel
        }

        self.state = .broadcasting(task: task, suspendedProducer: nil, channels: channels, isBusy: false, demands: demands)
        return actions
      case .finished:
        preconditionFailure("Invalid state.")
    }
  }

  mutating func finish(error: Error? = nil) -> [Channel.FinishAction] {
    switch state {
      case .initial:
        preconditionFailure("Invalid state.")
      case .broadcasting(_, _, var channels, _, _):
        var actions = [Channel.FinishAction]()
        for entry in channels {
          let id = entry.key
          var channel = entry.value
          actions.append(channel.finish(error: error))
          channels[id] = channel
        }

        self.state = .finished(channels: channels)
        return actions
      case .finished:
        preconditionFailure("Invalid state.")
    }
  }

  mutating func next(id: Int) -> Channel.NextAction {
    switch self.state {
      case .initial(let base, var channels):
        var channel = Channel()
        let action = channel.next()
        channels[id] = channel
        self.state = .initial(base: base, channels: channels)
        return action
      case .broadcasting(let task, let suspendedProducer, var channels, let isBusy, let demands):
        if var channel = channels[id] {
          let action = channel.next()
          channels[id] = channel

          self.state = .broadcasting(task: task, suspendedProducer: suspendedProducer, channels: channels, isBusy: isBusy, demands: demands)
          return action
        }
        var channel = Channel()
        let action = channel.next()
        channels[id] = channel

        self.state = .broadcasting(task: task, suspendedProducer: suspendedProducer, channels: channels, isBusy: isBusy, demands: demands)
        return action
      case .finished(var channels):
        if var channel = channels[id] {
          let action = channel.next()
          channels[id] = channel
          self.state = .finished(channels: channels)
          return action
        }
        var channel = Channel()
        let action = channel.next()
        channels[id] = channel

        self.state = .finished(channels: channels)
        return action
    }
  }

  enum NextIsSuspendedAction {
    case nextIsSuspendedAction(action: Channel.NextIsSuspendedAction)
    case resumeProducerAndNextIsSuspendedAction(continuation: UnsafeContinuation<Void, Never>?, action: Channel.NextIsSuspendedAction)
    case startTask(base: Base)
  }

  mutating func nextIsSuspended(
    id: Int,
    continuation: UnsafeContinuation<Result<Base.Element?, Error>, Never>
  ) -> NextIsSuspendedAction {
    switch self.state {
      case .initial(let base, _):
        return .startTask(base: base)
      case .broadcasting(let task, let suspendedProducer, var channels, let isBusy, var demands):
        guard channels[id] != nil else { return .nextIsSuspendedAction(action: .resume(element: .success(nil))) }

        if isBusy {
          demands.update(with: id)
          var channel = channels[id]!
          let action = channel.nextIsSuspended(continuation: continuation)
          channels[id] = channel

          self.state = .broadcasting(task: task, suspendedProducer: suspendedProducer, channels: channels, isBusy: isBusy, demands: demands)
          return .nextIsSuspendedAction(action: action)
        }
        demands.removeAll()
        var channel = channels[id]!
        let action = channel.nextIsSuspended(continuation: continuation)
        channels[id] = channel

        self.state = .broadcasting(task: task, suspendedProducer: suspendedProducer, channels: channels, isBusy: true, demands: demands)
        return .resumeProducerAndNextIsSuspendedAction(continuation: suspendedProducer, action: action)
      case .finished(var channels):
        precondition(channels[id] != nil, "Invalid state.")
        var channel = channels[id]!
        let action = channel.nextIsSuspended(continuation: continuation)
        channels[id] = channel

        self.state = .finished(channels: channels)
        return .nextIsSuspendedAction(action: action)
    }
  }

  enum NextIsCancelledAction {
    case nextIsCancelledAction(continuation: UnsafeContinuation<Result<Base.Element?, Error>, Never>?)
  }

  mutating func nextIsCancelled(
    id: Int
  ) -> NextIsCancelledAction {
    switch self.state {
      case .initial:
        preconditionFailure("Invalid state.")
      case .broadcasting(let task, let suspendedProducer, var channels, let isBusy, var demands):
        precondition(channels[id] != nil, "Invalid state.")
        var channel = channels[id]!
        demands.remove(id)
        let continuation = channel.nextIsCancelled()
        channels[id] = nil

        self.state = .broadcasting(task: task, suspendedProducer: suspendedProducer, channels: channels, isBusy: isBusy, demands: demands)
        return .nextIsCancelledAction(continuation: continuation)

      case .finished(var channels):
        var channel = channels[id]!
        let continuation = channel.nextIsCancelled()
        channels[id] = nil

        self.state = .finished(channels: channels)
        return .nextIsCancelledAction(continuation: continuation)
    }
  }
}

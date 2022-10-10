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

struct Zip2StateMachine<Element1, Element2>: Sendable
where Element1: Sendable, Element2: Sendable {
  typealias SuspendedDemand = UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>)?, Never>

  private enum State {
    case initial
    case awaitingDemandFromConsumer(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]
    )
    case awaitingBaseResults(
      task: Task<Void, Never>?,
      result1: Result<Element1, Error>?,
      result2: Result<Element2, Error>?,
      suspendedBases: [UnsafeContinuation<Void, Never>],
      suspendedDemand: SuspendedDemand?
    )
    case finished
  }

  private var state: State = .initial

  mutating func taskIsStarted(
    task: Task<Void, Never>,
    suspendedDemand: SuspendedDemand
  ) {
    switch self.state {
      case .initial:
        self.state = .awaitingBaseResults(
          task: task,
          result1: nil,
          result2: nil,
          suspendedBases: [],
          suspendedDemand: suspendedDemand
        )

      default:
        preconditionFailure("Inconsistent state, the task cannot start while the state is other than initial")
    }
  }

  enum NewDemandFromConsumerOutput {
    case resumeBases(suspendedBases: [UnsafeContinuation<Void, Never>])
    case startTask(suspendedDemand: SuspendedDemand)
    case terminate(suspendedDemand: SuspendedDemand)
  }

  mutating func newDemandFromConsumer(
    suspendedDemand: UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>)?, Never>
  ) -> NewDemandFromConsumerOutput {
    switch self.state {
      case .initial:
        return .startTask(suspendedDemand: suspendedDemand)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        self.state = .awaitingBaseResults(task: task, result1: nil, result2: nil, suspendedBases: [], suspendedDemand: suspendedDemand)
        return .resumeBases(suspendedBases: suspendedBases)

      case .awaitingBaseResults:
        preconditionFailure("Inconsistent state, a demand is already suspended")

      case .finished:
        return .terminate(suspendedDemand: suspendedDemand)
    }
  }

  enum NewLoopFromBaseOutput {
    case none
    case resumeBases(suspendedBases: [UnsafeContinuation<Void, Never>])
    case terminate(suspendedBase: UnsafeContinuation<Void, Never>)
  }

  mutating func newLoopFromBase1(suspendedBase: UnsafeContinuation<Void, Never>) -> NewLoopFromBaseOutput {
    switch self.state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer(let task, var suspendedBases):
        precondition(suspendedBases.count < 2, "There cannot be more than 2 suspended bases at the same time")
        suspendedBases.append(suspendedBase)
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)
        return .none

      case .awaitingBaseResults(let task, let result1, let result2, var suspendedBases, let suspendedDemand):
        precondition(suspendedBases.count < 2, "There cannot be more than 2 suspended bases at the same time")
        if result1 != nil {
          suspendedBases.append(suspendedBase)
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .resumeBases(suspendedBases: [suspendedBase])
        }

      case .finished:
        return .terminate(suspendedBase: suspendedBase)
    }
  }

  mutating func newLoopFromBase2(suspendedBase: UnsafeContinuation<Void, Never>) -> NewLoopFromBaseOutput {
    switch state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer(let task, var suspendedBases):
        precondition(suspendedBases.count < 2, "There cannot be more than 2 suspended bases at the same time")
        suspendedBases.append(suspendedBase)
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)
        return .none

      case .awaitingBaseResults(let task, let result1, let result2, var suspendedBases, let suspendedDemand):
        precondition(suspendedBases.count < 2, "There cannot be more than 2 suspended bases at the same time")
        if result2 != nil {
          suspendedBases.append(suspendedBase)
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .resumeBases(suspendedBases: [suspendedBase])
        }

      case .finished:
        return .terminate(suspendedBase: suspendedBase)
    }
  }

  enum BaseHasProducedElementOutput {
    case none
    case resumeDemand(
      suspendedDemand: SuspendedDemand?,
      result1: Result<Element1, Error>,
      result2: Result<Element2, Error>
    )
  }

  mutating func base1HasProducedElement(element: Element1) -> BaseHasProducedElementOutput {
    switch self.state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer:
        preconditionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")

      case .awaitingBaseResults(let task, _, let result2, let suspendedBases, let suspendedDemand):
        if let result2 {
          self.state = .awaitingBaseResults(
            task: task,
            result1: .success(element),
            result2: result2,
            suspendedBases: suspendedBases,
            suspendedDemand: nil
          )
          return .resumeDemand(suspendedDemand: suspendedDemand, result1: .success(element), result2: result2)
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: .success(element),
            result2: nil,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        }

      case .finished:
        return .none
    }
  }

  mutating func base2HasProducedElement(element: Element2) -> BaseHasProducedElementOutput {
    switch self.state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer:
        preconditionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")

      case .awaitingBaseResults(let task, let result1, _, let suspendedBases, let suspendedDemand):
        if let result1 {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: .success(element),
            suspendedBases: suspendedBases,
            suspendedDemand: nil
          )
          return .resumeDemand(suspendedDemand: suspendedDemand, result1: result1, result2: .success(element))
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: nil,
            result2: .success(element),
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        }

      case .finished:
        return .none
    }
  }

  enum BaseHasProducedFailureOutput {
    case none
    case resumeDemandAndTerminate(
      task: Task<Void, Never>?,
      suspendedDemand: SuspendedDemand?,
      suspendedBases: [UnsafeContinuation<Void, Never>],
      result1: Result<Element1, Error>,
      result2: Result<Element2, Error>
    )
  }

  mutating func baseHasProducedFailure(error: any Error) -> BaseHasProducedFailureOutput {
    switch self.state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer:
        preconditionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")

      case .awaitingBaseResults(let task, _, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .resumeDemandAndTerminate(
          task: task,
          suspendedDemand: suspendedDemand,
          suspendedBases: suspendedBases,
          result1: .failure(error),
          result2: .failure(error)
        )

      case .finished:
        return .none
    }
  }

  mutating func base2HasProducedFailure(error: Error) -> BaseHasProducedFailureOutput {
    switch self.state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer:
        preconditionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")

      case .awaitingBaseResults(let task, _, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .resumeDemandAndTerminate(
          task: task,
          suspendedDemand: suspendedDemand,
          suspendedBases: suspendedBases,
          result1: .failure(error),
          result2: .failure(error)
        )

      case .finished:
        return .none
    }
  }

  mutating func demandIsFulfilled() {
    switch self.state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer:
        preconditionFailure("Inconsistent state, results are not yet available to be acknowledged")

      case .awaitingBaseResults(let task, let result1, let result2, let suspendedBases, let suspendedDemand):
        precondition(suspendedDemand == nil, "Inconsistent state, there cannot be a suspended demand when ackowledging the demand")
        precondition(result1 != nil && result2 != nil, "Inconsistent state, all results are not yet available to be acknowledged")
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)

      case .finished:
        break
    }
  }

  enum RootTaskIsCancelledOutput {
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?,
      suspendedDemands: [SuspendedDemand?]?
    )
  }

  mutating func rootTaskIsCancelled() -> RootTaskIsCancelledOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: nil)

      case .awaitingBaseResults(let task, _, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: [suspendedDemand])

      case .finished:
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)
    }
  }

  enum BaseIsFinishedOutput {
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?,
      suspendedDemands: [SuspendedDemand?]?
    )
  }

  mutating func baseIsFinished() -> BaseIsFinishedOutput {
    switch self.state {
      case .initial:
        preconditionFailure("Inconsistent state, the task is not started")

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: nil)

      case .awaitingBaseResults(let task, _, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: [suspendedDemand])

      case .finished:
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)
    }
  }
}

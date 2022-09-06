//
//  MergeStateMachine.swift
//  
//
//  Created by Thibault Wittemberg on 08/09/2022.
//

import DequeModule

struct MergeStateMachine<Element>: Sendable {
  enum MergedElement {
    case element(Result<Element, Error>)
    case termination
  }

  enum BufferState {
    case idle
    case queued(Deque<MergedElement>)
    case awaiting(UnsafeContinuation<MergedElement, Never>)
    case closed
  }

  struct State {
    var buffer: BufferState
    var basesToTerminate: Int
  }

  struct OnNextDecision {
    let continuation: UnsafeContinuation<MergedElement, Never>
    let mergedElement: MergedElement
  }

  let requestNextRegulatedElements: @Sendable () -> Void
  let state: ManagedCriticalState<State>
  let task: Task<Void, Never>

  init<Base1: AsyncSequence, Base2: AsyncSequence>(
    _ base1: Base1,
    terminatesOnNil base1TerminatesOnNil: Bool = false,
    _ base2: Base2,
    terminatesOnNil base2TerminatesOnNil: Bool = false
  ) where Base1.Element == Element, Base2.Element == Element {
    self.state = ManagedCriticalState(State(buffer: .idle, basesToTerminate: 2))

    let regulator1 = Regulator(base1, onNextRegulatedElement: { [state] in Self.onNextRegulatedElement($0, state: state) })
    let regulator2 = Regulator(base2, onNextRegulatedElement: { [state] in Self.onNextRegulatedElement($0, state: state) })

    self.requestNextRegulatedElements = {
      regulator1.requestNextRegulatedElement()
      regulator2.requestNextRegulatedElement()
    }

    self.task = Task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          await regulator1.iterate(terminatesOnNil: base1TerminatesOnNil)
        }

        group.addTask {
          await regulator2.iterate(terminatesOnNil: base2TerminatesOnNil)
        }
      }
    }
  }

  init<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(
    _ base1: Base1,
    terminatesOnNil base1TerminatesOnNil: Bool = false,
    _ base2: Base2,
    terminatesOnNil base2TerminatesOnNil: Bool = false,
    _ base3: Base3,
    terminatesOnNil base3TerminatesOnNil: Bool = false
  ) where Base1.Element == Element, Base2.Element == Element, Base3.Element == Base1.Element {
    self.state = ManagedCriticalState(State(buffer: .idle, basesToTerminate: 3))

    let regulator1 = Regulator(base1, onNextRegulatedElement: { [state] in Self.onNextRegulatedElement($0, state: state) })
    let regulator2 = Regulator(base2, onNextRegulatedElement: { [state] in Self.onNextRegulatedElement($0, state: state) })
    let regulator3 = Regulator(base3, onNextRegulatedElement: { [state] in Self.onNextRegulatedElement($0, state: state) })

    self.requestNextRegulatedElements = {
      regulator1.requestNextRegulatedElement()
      regulator2.requestNextRegulatedElement()
      regulator3.requestNextRegulatedElement()
    }

    self.task = Task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          await regulator1.iterate(terminatesOnNil: base1TerminatesOnNil)
        }

        group.addTask {
          await regulator2.iterate(terminatesOnNil: base2TerminatesOnNil)
        }

        group.addTask {
          await regulator3.iterate(terminatesOnNil: base3TerminatesOnNil)
        }
      }
    }
  }

  init<Base: AsyncSequence>(
    _ bases: [Base]
  ) where Base.Element == Element {
    self.state = ManagedCriticalState(State(buffer: .idle, basesToTerminate: bases.count))

    var regulators = [Regulator<Base>]()

    for base in bases {
      let regulator = Regulator<Base>(base, onNextRegulatedElement: { [state] in Self.onNextRegulatedElement($0, state: state) })
      regulators.append(regulator)
    }

    let immutableRegulators = regulators
    self.requestNextRegulatedElements = {
      for regulator in immutableRegulators {
        regulator.requestNextRegulatedElement()
      }
    }

    self.task = Task {
      await withTaskGroup(of: Void.self) { group in
        for regulators in immutableRegulators {
          group.addTask {
            await regulators.iterate(terminatesOnNil: false)
          }
        }
      }
    }
  }

  @Sendable static func onNextRegulatedElement(_ element: RegulatedElement<Element>, state: ManagedCriticalState<State>) {
    let decision = state.withCriticalRegion { state -> OnNextDecision? in
      switch (state.buffer, element) {
        // when buffer is close
        case (.closed, _):
          return nil

        // when buffer is empty and available
        case (.idle, .termination(let forcedTermination)) where forcedTermination == true:
          state.basesToTerminate = 0
          state.buffer = .closed
          return nil
        case (.idle, .termination):
          state.basesToTerminate -= 1
          if state.basesToTerminate == 0 {
            state.buffer = .closed
          } else {
            state.buffer = .idle
          }
          return nil
        case (.idle, .element(let result)):
          state.buffer = .queued([.element(result)])
          return nil

        // when buffer is queued
        case (.queued(var elements), .termination(let forcedTermination)) where forcedTermination == true:
          elements.append(.termination)
          state.buffer = .queued(elements)
          return nil
        case (.queued(var elements), .termination):
          state.basesToTerminate -= 1
          if state.basesToTerminate == 0 {
            elements.append(.termination)
            state.buffer = .queued(elements)
          }
          return nil
        case (.queued(var elements), .element(let result)):
          elements.append(.element(result))
          state.buffer = .queued(elements)
          return nil

        // when buffer is awaiting for base values
        case (.awaiting(let continuation), .termination(let forcedTermination)) where forcedTermination == true:
          state.basesToTerminate = 0
          state.buffer = .closed
          return OnNextDecision(continuation: continuation, mergedElement: .termination)
        case (.awaiting(let continuation), .termination):
          state.basesToTerminate -= 1
          if state.basesToTerminate == 0 {
            state.buffer = .closed
            return OnNextDecision(continuation: continuation, mergedElement: .termination)
          } else {
            state.buffer = .awaiting(continuation)
            return nil
          }
        case (.awaiting(let continuation), .element(.success(let element))):
          state.buffer = .idle
          return OnNextDecision(continuation: continuation, mergedElement: .element(.success(element)))
        case (.awaiting(let continuation), .element(.failure(let error))):
          state.buffer = .closed
          return OnNextDecision(continuation: continuation, mergedElement: .element(.failure(error)))
      }
    }

    if let decision = decision {
      decision.continuation.resume(returning: decision.mergedElement)
    }
  }

  @Sendable func unsuspendAndClearOnCancel() {
    let continuation = self.state.withCriticalRegion { state -> UnsafeContinuation<MergedElement, Never>? in
      switch state.buffer {
        case .awaiting(let continuation):
          state.basesToTerminate = 0
          state.buffer = .closed
          return continuation
        default:
          state.basesToTerminate = 0
          state.buffer = .closed
          return nil
      }
    }

    continuation?.resume(returning: .termination)
    self.task.cancel()
  }

  func next() async -> MergedElement {
    await withTaskCancellationHandler {
      self.unsuspendAndClearOnCancel()
    } operation: {
      self.requestNextRegulatedElements()

      let mergedElement = await withUnsafeContinuation { (continuation: UnsafeContinuation<MergedElement, Never>) in
        let decision = self.state.withCriticalRegion { state -> OnNextDecision? in
          switch state.buffer {
            case .closed:
              return OnNextDecision(continuation: continuation, mergedElement: .termination)
            case .idle:
              state.buffer = .awaiting(continuation)
              return nil
            case .queued(var elements):
              guard let mergedElement = elements.popFirst() else {
                assertionFailure("The buffer cannot by empty, it should be idle in this case")
                return OnNextDecision(continuation: continuation, mergedElement: .termination)
              }
              switch mergedElement {
                case .termination:
                  state.buffer = .closed
                  return OnNextDecision(continuation: continuation, mergedElement: .termination)
                case .element(.success(let element)):
                  if elements.isEmpty {
                    state.buffer = .idle
                  } else {
                    state.buffer = .queued(elements)
                  }
                  return OnNextDecision(continuation: continuation, mergedElement: .element(.success(element)))
                case .element(.failure(let error)):
                  state.buffer = .closed
                  return OnNextDecision(continuation: continuation, mergedElement: .element(.failure(error)))
              }
            case .awaiting:
              assertionFailure("The next function cannot be called concurrently")
              return OnNextDecision(continuation: continuation, mergedElement: .termination)
          }
        }

        if let decision = decision {
          decision.continuation.resume(returning: decision.mergedElement)
        }
      }

      if case .termination = mergedElement, case .element(.failure) = mergedElement {
        self.task.cancel()
      }

      return mergedElement
    }
  }
}

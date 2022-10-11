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

final class Zip3Runtime<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable, Base3: Sendable, Base3.Element: Sendable {
  typealias ZipStateMachine = Zip3StateMachine<Base1.Element, Base2.Element, Base3.Element>

  private let stateMachine = ManagedCriticalState(ZipStateMachine())
  private let base1: Base1
  private let base2: Base2
  private let base3: Base3

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }

  func next() async rethrows -> (Base1.Element, Base2.Element, Base3.Element)? {
    try await withTaskCancellationHandler {
      let results = await withUnsafeContinuation { continuation in
        self.stateMachine.withCriticalRegion { stateMachine in
          let output = stateMachine.newDemandFromConsumer(suspendedDemand: continuation)
          switch output {
            case .startTask(let suspendedDemand):
              // first iteration, we start one task per base to iterate over them
              self.startTask(stateMachine: &stateMachine, suspendedDemand: suspendedDemand)

            case .resumeBases(let suspendedBases):
              // bases can be iterated over for 1 iteration so their next value can be retrieved
              suspendedBases.forEach { $0.resume() }

            case .terminate(let suspendedDemand):
              // the async sequence is already finished, immediately resuming
              suspendedDemand.resume(returning: nil)
          }
        }
      }

      guard let results else {
        return nil
      }

      self.stateMachine.withCriticalRegion { stateMachine in
        // acknowledging the consumption of the zipped values, so we can begin another iteration on the bases
        stateMachine.demandIsFulfilled()
      }

      return try (results.0._rethrowGet(), results.1._rethrowGet(), results.2._rethrowGet())
    } onCancel: {
      let output = self.stateMachine.withCriticalRegion { stateMachine in
        stateMachine.rootTaskIsCancelled()
      }
      // clean the allocated resources and state
      self.handle(rootTaskIsCancelledOutput: output)
    }
  }

  private func handle(rootTaskIsCancelledOutput: ZipStateMachine.RootTaskIsCancelledOutput) {
    switch rootTaskIsCancelledOutput {
      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0?.resume(returning: nil) }
        task?.cancel()
    }
  }

  private func startTask(
    stateMachine: inout ZipStateMachine,
    suspendedDemand: ZipStateMachine.SuspendedDemand
  ) {
    let task = Task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          var base1Iterator = self.base1.makeAsyncIterator()

          do {
            while true {
              await withUnsafeContinuation { continuation in
                let output = self.stateMachine.withCriticalRegion { machine in
                  machine.newLoopFromBase1(suspendedBase: continuation)
                }

                self.handle(newLoopFromBaseOutput: output)
              }

              guard let element1 = try await base1Iterator.next() else {
                break
              }

              let output = self.stateMachine.withCriticalRegion { machine in
                machine.base1HasProducedElement(element: element1)
              }

              self.handle(baseHasProducedElementOutput: output)
            }
          } catch {
            let output = self.stateMachine.withCriticalRegion { machine in
              machine.baseHasProducedFailure(error: error)
            }

            self.handle(baseHasProducedFailureOutput: output)
          }

          let output = self.stateMachine.withCriticalRegion { stateMachine in
            stateMachine.baseIsFinished()
          }

          self.handle(baseIsFinishedOutput: output)
        }

        group.addTask {
          var base2Iterator = self.base2.makeAsyncIterator()

          do {
            while true {
              await withUnsafeContinuation { continuation in
                let output = self.stateMachine.withCriticalRegion { machine in
                  machine.newLoopFromBase2(suspendedBase: continuation)
                }

                self.handle(newLoopFromBaseOutput: output)
              }

              guard let element2 = try await base2Iterator.next() else {
                break
              }

              let output = self.stateMachine.withCriticalRegion { machine in
                machine.base2HasProducedElement(element: element2)
              }

              self.handle(baseHasProducedElementOutput: output)
            }
          } catch {
            let output = self.stateMachine.withCriticalRegion { machine in
              machine.baseHasProducedFailure(error: error)
            }

            self.handle(baseHasProducedFailureOutput: output)
          }

          let output = self.stateMachine.withCriticalRegion { machine in
            machine.baseIsFinished()
          }

          self.handle(baseIsFinishedOutput: output)
        }

        group.addTask {
          var base3Iterator = self.base3.makeAsyncIterator()

          do {
            while true {
              await withUnsafeContinuation { continuation in
                let output = self.stateMachine.withCriticalRegion { machine in
                  machine.newLoopFromBase3(suspendedBase: continuation)
                }

                self.handle(newLoopFromBaseOutput: output)
              }

              guard let element3 = try await base3Iterator.next() else {
                break
              }

              let output = self.stateMachine.withCriticalRegion { machine in
                machine.base3HasProducedElement(element: element3)
              }

              self.handle(baseHasProducedElementOutput: output)
            }
          } catch {
            let output = self.stateMachine.withCriticalRegion { machine in
              machine.baseHasProducedFailure(error: error)
            }

            self.handle(baseHasProducedFailureOutput: output)
          }

          let output = self.stateMachine.withCriticalRegion { machine in
            machine.baseIsFinished()
          }

          self.handle(baseIsFinishedOutput: output)
        }
      }
    }
    stateMachine.taskIsStarted(task: task, suspendedDemand: suspendedDemand)
  }

  private func handle(newLoopFromBaseOutput: ZipStateMachine.NewLoopFromBaseOutput) {
    switch newLoopFromBaseOutput {
      case .none:
        break

      case .resumeBases(let suspendedBases):
        suspendedBases.forEach { $0.resume() }

      case .terminate(let suspendedBase):
        suspendedBase.resume()
    }
  }

  private func handle(baseHasProducedElementOutput: ZipStateMachine.BaseHasProducedElementOutput) {
    switch baseHasProducedElementOutput {
      case .none:
        break

      case .resumeDemand(let suspendedDemand, let result1, let result2, let result3):
        suspendedDemand?.resume(returning: (result1, result2, result3))
    }
  }

  private func handle(baseHasProducedFailureOutput: ZipStateMachine.BaseHasProducedFailureOutput) {
    switch baseHasProducedFailureOutput {
      case .none:
        break

      case .resumeDemandAndTerminate(let task, let suspendedDemand, let suspendedBases, let result1, let result2, let result3):
        suspendedDemand?.resume(returning: (result1, result2, result3))
        suspendedBases.forEach { $0.resume() }
        task?.cancel()
    }
  }

  private func handle(baseIsFinishedOutput: ZipStateMachine.BaseIsFinishedOutput) {
    switch baseIsFinishedOutput {
      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0?.resume(returning: nil) }
        task?.cancel()
    }
  }

  deinit {
    // clean the allocated resources and state
    let output = self.stateMachine.withCriticalRegion { stateMachine in
      stateMachine.rootTaskIsCancelled()
    }

    self.handle(rootTaskIsCancelledOutput: output)
  }
}

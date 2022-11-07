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

// ALGORITHM SUMMARY:
//
// The basic idea behind the `AsyncSharedSequence` algorithm is as follows:
// Every vended `AsyncSharedSequence` iterator (runner) takes part in a race
// (run group) to grab the next element from the base iterator. The 'winner'
// returns the element to the shared state, who then supplies the result to
// later finishers (other iterators). Once every runner has completed the
// current run group cycle, the next run group begins. This means that
// iterators run in lock-step, only moving forward when the the last iterator
// in the run group completes its current run (iteration).
//
// ITERATOR LIFECYCLE:
//
//  1. CONNECTION: On connection, each 'runner' is issued with an ID (and any
//     prefixed values from the history buffer). From this point on, the
//     algorithm will wait on this iterator to consume its values before moving
//     on. This means that until `next()` is called on this iterator, all the
//     other iterators will be held until such time that it is, or the
//     iterator's task is cancelled.
//
//  2. RUN: After its prefix values have been exhausted, each time `next()` is
//     called on the iterator, the iterator attempts to start a 'run' by
//     calling `startRun(_:)` on the shared state. The shared state marks the
//     iterator as 'running' and issues a role to determine the iterator's
//     action for the current run group. The roles are as follows:
//
//       - FETCH: The iterator is the 'winner' of this run group. It is issued
//         with the 'borrowed' base iterator. It calls `next()` on it and,
//         once it resumes, returns the value and the borrowed base iterator
//         to the shared state.
//       – WAIT: The iterator hasn't won this group, but was fast enough that
//         the winner has yet to resume with the element from the base
//         iterator. Therefore, it is told to suspend (WAIT) until such time
//         that the winner resumes.
//       – YIELD: The iterator is late (and is holding up the other iterators).
//         The shared state issues it with the value retrieved by the winning
//         iterator and lets it continue immediately.
//       – HOLD: The iterator is early for the next run group. So it is put in
//         the holding pen until the next run group can start. This is because
//         there are other iterators that still haven't finished their run for
//         the current run group. Once all other iterators have completed their
//         run, this iterator will be resumed.
//
//  3. COMPLETION: The iterator calls cancel on the shared state which ensures
//     the iterator does not take part in the next run group. However, if it is
//     currently suspended it may not resume until the current run group
//     concludes. This is especially important if it is filling the key FETCH
//     role for the current run group.

// MARK: - Member Function

import DequeModule

extension AsyncSequence where Self: Sendable, Element: Sendable {
  
  /// Creates an asynchronous sequence that can be shared by multiple consumers.
  ///
  /// - parameter history: the number of previously emitted elements to prefix
  ///   to the iterator of a new consumer
  /// - parameter iteratorDisposalPolicy:the iterator disposal policy applied by
  ///   a shared asynchronous sequence to its upstream iterator
  public func share(
    history historyCount: Int = 0,
    disposingBaseIterator iteratorDisposalPolicy: AsyncSharedSequence<Self>.IteratorDisposalPolicy = .whenTerminatedOrVacant
  ) -> AsyncSharedSequence<Self> {
    AsyncSharedSequence(
      self, history: historyCount, disposingBaseIterator: iteratorDisposalPolicy)
  }
}

// MARK: - Sequence

/// An asynchronous sequence that can be iterated by multiple concurrent
/// consumers.
///
/// Use a shared asynchronous sequence when you have multiple downstream
/// asynchronous sequences with which you wish to share the output of a single
/// asynchronous sequence. This can be useful if you have expensive upstream
/// operations, or if your asynchronous sequence represents the output of a
/// physical device.
///
/// Elements are emitted from a shared asynchronous sequence at a rate that does
/// not exceed the consumption of its slowest consumer. If this kind of
/// back-pressure isn't desirable for your use-case, ``AsyncSharedSequence`` can
/// be composed with buffers – either upstream, downstream, or both – to acheive
/// the desired behavior.
///
/// If you have an asynchronous sequence that consumes expensive system
/// resources, it is possible to configure ``AsyncSharedSequence`` to discard
/// its upstream iterator when the connected downstream consumer count falls to
/// zero. This allows any cancellation tasks configured on the upstream
/// asynchronous sequence to be initiated and for expensive resources to be
/// terminated. ``AsyncSharedSequence`` will re-create a fresh iterator if there
/// is further demand.
///
/// For use-cases where it is important for consumers to have a record of
/// elements emitted prior to their connection, a ``AsyncSharedSequence`` can
/// also be configured to prefix its output with the most recently emitted
/// elements. If ``AsyncSharedSequence`` is configured to drop its iterator when
/// the connected consumer count falls to zero, its history will be discarded at
/// the same time.
public struct AsyncSharedSequence<Base: AsyncSequence> : Sendable
  where Base: Sendable, Base.Element: Sendable {
  
  /// The iterator disposal policy applied by a shared asynchronous sequence to
  /// its upstream iterator
  ///
  /// - note: the iterator is always disposed when the base asynchronous
  ///   sequence terminates
  public enum IteratorDisposalPolicy: Sendable {
    /// retains the upstream iterator for use by future consumers until the base
    /// asynchronous sequence is terminated
    case whenTerminated
    /// discards the upstream iterator when the number of consumers falls to
    /// zero or the base asynchronous sequence is terminated
    case whenTerminatedOrVacant
  }
  
  private let base: Base
  private let state: State
  private let deallocToken: DeallocToken
  
  /// Contructs a shared asynchronous sequence
  ///
  /// - parameter base: the asynchronous sequence to be shared
  /// - parameter history: the number of previously emitted elements to prefix
  ///   to the iterator of a new consumer
  /// - parameter iteratorDisposalPolicy: the iterator disposal policy applied
  ///   to the upstream iterator
  public init(
    _ base: Base,
    history historyCount: Int = 0,
    disposingBaseIterator iteratorDisposalPolicy: IteratorDisposalPolicy = .whenTerminatedOrVacant
  ) {
    let state = State(
      base, replayCount: historyCount, iteratorDisposalPolicy: iteratorDisposalPolicy)
    self.base = base
    self.state = state
    self.deallocToken = .init { state.abort() }
  }
}

// MARK: - Iterator

extension AsyncSharedSequence: AsyncSequence {
  
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol {
    
    private let id: UInt
    private let deallocToken: DeallocToken?
    private var prefix: Deque<Element>
    private var state: State?
    
    fileprivate init(_ state: State) {
      switch state.establish() {
      case .active(let id, let prefix):
        self.id = id
        self.prefix = prefix
        self.deallocToken = .init { state.cancel(id) }
        self.state = state
      case .terminal(let id):
        self.id = id
        self.prefix = .init()
        self.deallocToken = nil
        self.state = nil
      }
    }
    
    public mutating func next() async rethrows -> Element? {
      do {
        return try await withTaskCancellationHandler {
          if prefix.isEmpty == false, let element = prefix.popFirst() {
            return element
          }
          guard let state else { return nil }
          let role = state.startRun(id)
          switch role {
          case .fetch(let iterator):
            let upstreamResult = await iterator.next()
            let output = state.fetch(
              id, resumedWithResult: upstreamResult, iterator: iterator)
            return try processOutput(output)
          case .wait:
            let output = await withUnsafeContinuation { continuation in
              let immediateOutput = state.wait(
                id, suspendedWithContinuation: continuation)
              if let immediateOutput {
                continuation.resume(returning: immediateOutput)
              }
            }
            return try processOutput(output)
          case .yield(let output):
            return try processOutput(output)
          case .hold:
            await withUnsafeContinuation { continuation in
              let shouldImmediatelyResume = state.hold(
                id, suspendedWithContinuation: continuation)
              if shouldImmediatelyResume { continuation.resume() }
            }
            return try await next()
          }
        } onCancel: { [state, id] in
          state?.cancel(id)
        }
      }
      catch {
        self.state = nil
        throw error
      }
    }
    
    private mutating func processOutput(
      _ output: RunOutput
    ) rethrows -> Element? {
      if output.shouldCancel {
        self.state = nil
      }
      do {
        guard let element = try output.value._rethrowGet() else {
          self.state = nil
          return nil
        }
        return element
      }
      catch {
        self.state = nil
        throw error
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(state)
  }
}

// MARK: - State

fileprivate extension AsyncSharedSequence {
  
  enum RunnerConnection {
    case active(id: UInt, prefix: Deque<Element>)
    case terminal(id: UInt)
  }
  
  enum RunRole {
    case fetch(SharedUpstreamIterator)
    case wait
    case yield(RunOutput)
    case hold
  }
  
  struct RunOutput {
    let value: Result<Element?, Error>
    var shouldCancel = false
  }
  
  actor SharedUpstreamIterator {
    
    private enum State {
      case pending
      case active(Base.AsyncIterator)
      case terminal
    }
    
    private let base: Base
    private var state = State.pending
    
    init(_ base: Base) {
      self.base = base
    }
    
    func next() async -> Result<Element?, Error> {
      switch state {
      case .pending:
        self.state = .active(base.makeAsyncIterator())
        return await next()
      case .active(var iterator):
        do {
          if let element = try await iterator.next() {
            self.state = .active(iterator)
            return .success(element)
          }
          else {
            self.state = .terminal
            return .success(nil)
          }
        }
        catch {
          self.state = .terminal
          return .failure(error)
        }
      case .terminal:
        return .success(nil)
      }
    }
  }
  
  struct State: Sendable {
    
    private struct RunContinuation {
      var held: [UnsafeContinuation<Void, Never>]?
      var waiting: [(UnsafeContinuation<RunOutput, Never>, RunOutput)]?
      func resume() {
        if let held {
          for continuation in held { continuation.resume() }
        }
        if let waiting {
          for (continuation, output) in waiting {
            continuation.resume(returning: output)
          }
        }
      }
    }
    
    private struct Storage: Sendable {
      
      enum Phase {
        case pending
        case fetching
        case done(Result<Element?, Error>)
      }
      
      struct Runner {
        var group: Int
        var active = false
        var cancelled = false
      }
      
      let base: Base
      let replayCount: Int
      let iteratorDiscardPolicy: IteratorDisposalPolicy
      var iterator: SharedUpstreamIterator?
      var nextRunnerID = UInt.min
      var currentGroup = 0
      var nextGroup: Int { (currentGroup + 1) % 2 }
      var history = Deque<Element>()
      var runners = [UInt: Runner]()
      var heldRunnerContinuations = [UnsafeContinuation<Void, Never>]()
      var waitingRunnerContinuations = [UInt: UnsafeContinuation<RunOutput, Never>]()
      var phase = Phase.pending
      var terminal = false
      
      init(
        _ base: Base,
        replayCount: Int,
        iteratorDisposalPolicy: IteratorDisposalPolicy
      ) {
        precondition(replayCount >= 0, "history must be greater than or equal to zero")
        self.base = base
        self.replayCount = replayCount
        self.iteratorDiscardPolicy = iteratorDisposalPolicy
        self.iterator = .init(base)
      }
      
      mutating func establish() -> (RunnerConnection, RunContinuation?) {
        defer { nextRunnerID += 1}
        if terminal {
          return (.terminal(id: nextRunnerID), nil)
        }
        else {
          let group: Int
          if case .done(_) = phase { group = nextGroup } else { group = currentGroup }
          runners[nextRunnerID] = .init(group: group)
          let connection = RunnerConnection.active(
            id: nextRunnerID, prefix: history)
          let continuation = RunContinuation(held: finalizeRunGroupIfNeeded())
          return (connection, continuation)
        }
      }
      
      mutating func run(_ runnerID: UInt) -> (RunRole, RunContinuation?) {
        guard terminal == false, let runner = runners[runnerID], runner.cancelled == false else {
          if case .done(let result) = phase {
            return (.yield(RunOutput(value: result, shouldCancel: true)), nil)
          }
          return (.yield(RunOutput(value: .success(nil), shouldCancel: true)), nil)
        }
        if runner.group == currentGroup {
          let updatedRunner = Runner(
            group: runner.group, active: true, cancelled: runner.cancelled)
          runners.updateValue(updatedRunner, forKey: runnerID)
          switch phase {
          case .pending:
            guard let iterator = iterator else {
              preconditionFailure("iterator must not be over-borrowed")
            }
            self.iterator = nil
            phase = .fetching
            return (.fetch(iterator), nil)
          case .fetching:
            return (.wait, nil)
          case .done(let result):
            finish(runnerID)
            let role = RunRole.yield(
              RunOutput(value: result, shouldCancel: runner.cancelled)
            )
            return (role, .init(held: finalizeRunGroupIfNeeded()))
          }
        }
        else {
          return (.hold, nil)
        }
      }
      
      mutating func fetch(
        _ runnerID: UInt,
        resumedWithResult result: Result<Element?, Error>,
        iterator: SharedUpstreamIterator
      ) -> (RunOutput, RunContinuation) {
        precondition(self.iterator == nil, "iterator is already in place")
        guard let runner = runners[runnerID] else {
          preconditionFailure("fetching runner resumed out of band")
        }
        self.iterator = iterator
        self.terminal = self.terminal || ((try? result.get()) == nil)
        self.phase = .done(result)
        finish(runnerID)
        updateHistory(withResult: result)
        var continuation = gatherWaitingRunnerContinuationsForResumption(
          withResult: result)
        continuation.held = finalizeRunGroupIfNeeded()
        let ouput = RunOutput(value: result, shouldCancel: runner.cancelled)
        return (ouput, continuation)
      }
      
      mutating func wait(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: UnsafeContinuation<RunOutput, Never>
      ) -> (RunOutput, RunContinuation)? {
        switch phase {
        case .fetching:
          waitingRunnerContinuations[runnerID] = continuation
          return nil
        case .done(let result):
          guard let runner = runners[runnerID] else {
            preconditionFailure("waiting runner resumed out of band")
          }
          finish(runnerID)
          let output = RunOutput(value: result, shouldCancel: runner.cancelled)
          let continuation = RunContinuation(held: finalizeRunGroupIfNeeded())
          return (output, continuation)
        default:
          preconditionFailure("waiting runner suspended out of band")
        }
      }
      
      private mutating func gatherWaitingRunnerContinuationsForResumption(
        withResult result: Result<Element?, Error>
      ) -> RunContinuation {
        let continuationPairs = waitingRunnerContinuations
          .map { waitingRunnerID, continuation in
            guard let waitingRunner = runners[waitingRunnerID] else {
              preconditionFailure("waiting runner resumed out of band")
            }
            finish(waitingRunnerID)
            let output = RunOutput(
              value: result, shouldCancel: waitingRunner.cancelled)
            return (continuation, output)
          }
        waitingRunnerContinuations.removeAll()
        return .init(waiting: continuationPairs)
      }
      
      mutating func hold(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: UnsafeContinuation<Void, Never>
      ) -> Bool {
        guard let runner = runners[runnerID], runner.group == nextGroup else {
          return true
        }
        heldRunnerContinuations.append(continuation)
        return false
      }
      
      private mutating func finish(_ runnerID: UInt) {
        guard var runner = runners.removeValue(forKey: runnerID) else {
          preconditionFailure("run finished out of band")
        }
        if runner.cancelled == false {
          runner.active = false
          runner.group = nextGroup
          runners[runnerID] = runner
        }
      }
      
      mutating func cancel(_ runnerID: UInt) -> RunContinuation? {
        if let runner = runners.removeValue(forKey: runnerID), runner.active {
          runners[runnerID] = .init(
            group: runner.group, active: true, cancelled: true)
          return nil
        }
        else {
          return .init(held: finalizeRunGroupIfNeeded())
        }
      }
      
      mutating func abort() -> RunContinuation {
        terminal = true
        runners = runners.filter { _, runner in runner.active }
        return .init(held: finalizeRunGroupIfNeeded())
      }
      
      private mutating func finalizeRunGroupIfNeeded(
      ) -> [UnsafeContinuation<Void, Never>]? {
        if (runners.values.contains { $0.group == currentGroup }) { return nil }
        if terminal {
          self.phase = .done(.success(nil))
          self.iterator = nil
          self.history.removeAll()
        }
        else {
          self.currentGroup = nextGroup
          self.phase = .pending
          if runners.isEmpty && iteratorDiscardPolicy == .whenTerminatedOrVacant {
            self.iterator = SharedUpstreamIterator(base)
            self.history.removeAll()
          }
        }
        let continuations = heldRunnerContinuations
        heldRunnerContinuations.removeAll()
        return continuations
      }
      
      private mutating func updateHistory(
        withResult result: Result<Element?, Error>
      ) {
        guard replayCount > 0, case .success(let element?) = result else {
          return
        }
        if history.count >= replayCount {
          history.removeFirst()
        }
        history.append(element)
      }
    }
    
    private let storage: ManagedCriticalState<Storage>
    
    init(
      _ base: Base,
      replayCount: Int,
      iteratorDisposalPolicy: IteratorDisposalPolicy
    ) {
      self.storage = .init(
        Storage(
          base,
          replayCount: replayCount,
          iteratorDisposalPolicy: iteratorDisposalPolicy
        )
      )
    }
    
    func establish() -> RunnerConnection {
      let (connection, continuation) = storage.withCriticalRegion {
        storage in storage.establish()
      }
      continuation?.resume()
      return connection
    }
    
    func startRun(_ runnerID: UInt) -> RunRole {
      let (role, continuation) = storage.withCriticalRegion {
        storage in storage.run(runnerID)
      }
      continuation?.resume()
      return role
    }
    
    func fetch(
      _ runnerID: UInt,
      resumedWithResult result: Result<Element?, Error>,
      iterator: SharedUpstreamIterator
    ) -> RunOutput {
      let (output, continuation) = storage.withCriticalRegion { storage in
        storage.fetch(runnerID, resumedWithResult: result, iterator: iterator)
      }
      continuation.resume()
      return output
    }
    
    func wait(
      _ runnerID: UInt,
      suspendedWithContinuation continuation: UnsafeContinuation<RunOutput, Never>
    ) -> RunOutput? {
      guard let (output, continuation) = storage.withCriticalRegion({ storage in
        storage.wait(runnerID, suspendedWithContinuation: continuation)
      }) else { return nil }
      continuation.resume()
      return output
    }
    
    func hold(
      _ runnerID: UInt,
      suspendedWithContinuation continuation: UnsafeContinuation<Void, Never>
    ) -> Bool {
      storage.withCriticalRegion { storage in
        storage.hold(runnerID, suspendedWithContinuation: continuation)
      }
    }
    
    func cancel(_ runnerID: UInt) {
      let continuation = storage.withCriticalRegion { storage in
        storage.cancel(runnerID)
      }
      continuation?.resume()
    }
    
    func abort() {
      let continuation = storage.withCriticalRegion {
        storage in storage.abort()
      }
      continuation.resume()
    }
  }
}

// MARK: - Utilities

fileprivate final class DeallocToken: Sendable {
  let action: @Sendable () -> Void
  init(_ dealloc: @escaping @Sendable () -> Void) {
    self.action = dealloc
  }
  deinit { action() }
}

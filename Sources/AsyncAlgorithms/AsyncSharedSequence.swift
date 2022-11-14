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
// The idea behind the `AsyncSharedSequence` algorithm is as follows: Vended
// iterators of `AsyncSharedSequence` are known as 'runners'. Runners compete
// in a race to grab the next element from a base iterator for each of its
// iteration cycles. The 'winner' of an iteration cycle returns the element to
// the shared context which then supplies the result to later finishers. Once
// every runner has finished, the current cycle completes and the next
// iteration can start. This means that runners move forward in lock-step, only
// proceeding when the the last runner in the current iteration has received a
// value or has cancelled.
//
// `AsyncSharedSequence` ITERATOR LIFECYCLE:
//
//  1. CONNECTION: On connection, each 'runner' is issued with an ID (and any
//     prefixed values from the history buffer) by the shared context. From
//     this point on, the algorithm will wait on this iterator to consume its
//     values before moving on. This means that until `next()` is called on
//     this iterator, all the other iterators will be held until such time that
//     it is, or the iterator's task is cancelled.
//
//  2. RUN: After its prefix values have been exhausted, each time `next()` is
//     called on the iterator, the iterator attempts to start a 'run' by
//     calling `startRun(_:)` on the shared context. The shared context marks
//     the iterator as 'running' and issues a role to determine the iterator's
//     action for the current iteration cycle. The roles are as follows:
//
//       - FETCH: The iterator is the 'winner' of this iteration cycle. It is
//         issued with the shared base iterator, calls `next()` on it, and
//         once it resumes returns the value to the shared context.
//       – WAIT: The iterator hasn't won this cycle, but was fast enough that
//         the winner has yet to resume with the element from the base
//         iterator. Therefore, it is told to suspend (WAIT) until such time
//         that the winner resumes.
//       – YIELD: The iterator is late (and is holding up the other iterators).
//         The shared context issues it with the value retrieved by the winning
//         iterator and lets it continue immediately.
//       – HOLD: The iterator is early for the next iteration cycle. So it is
//         put in the holding pen until the next cycle can start. This is
//         because there are other iterators that still haven't finished their
//         run for the current iteration cycle. This iterator will be resumed
//         when all other iterators have completed their run
//
//  3. COMPLETION: The iterator calls cancel on the shared context which
//     ensures the iterator does not take part in the next iteration cycle.
//     However, if it is currently suspended it may not resume until the
//     current iteration cycle concludes. This is especially important if it is
//     filling the key FETCH role for the current iteration cycle.

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
  
  private let context: Context
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
    let context = Context(
      base, replayCount: historyCount, iteratorDisposalPolicy: iteratorDisposalPolicy)
    self.context = context
    self.deallocToken = .init { context.abort() }
  }
}

// MARK: - Iterator

extension AsyncSharedSequence: AsyncSequence {
  
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol {
    
    private let id: UInt
    private let deallocToken: DeallocToken?
    private var prefix: Deque<Element>
    private var context: Context?
    
    fileprivate init(_ storage: Context) {
      switch storage.establish() {
      case .active(let id, let prefix):
        self.id = id
        self.prefix = prefix
        self.deallocToken = .init { storage.cancel(id) }
        self.context = storage
      case .terminal:
        self.id = UInt.min
        self.prefix = .init()
        self.deallocToken = nil
        self.context = nil
      }
    }
    
    public mutating func next() async rethrows -> Element? {
      do {
        return try await withTaskCancellationHandler {
          if prefix.isEmpty == false, let element = prefix.popFirst() {
            return element
          }
          guard let context else { return nil }
          let role = context.startRun(id)
          switch role {
          case .fetch(let iterator):
            let upstreamResult = await iterator.next()
            let output = context.fetch(id, resumedWithResult: upstreamResult)
            return try processOutput(output)
          case .wait:
            let output = await context.wait(id)
            return try processOutput(output)
          case .yield(let output):
            return try processOutput(output)
          case .hold:
            await context.hold(id)
            return try await next()
          }
        } onCancel: { [context, id] in
          context?.cancel(id)
        }
      }
      catch {
        self.context = nil
        throw error
      }
    }
    
    private mutating func processOutput(
      _ output: Context.RunOutput
    ) rethrows -> Element? {
      if output.shouldCancel {
        self.context = nil
      }
      do {
        guard let element = try output.value._rethrowGet() else {
          self.context = nil
          return nil
        }
        return element
      }
      catch {
        self.context = nil
        throw error
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(context)
  }
}

// MARK: - Context

private extension AsyncSharedSequence {
  
  struct Context: Sendable {
    
    typealias WaitContinuation = UnsafeContinuation<RunOutput, Never>
    typealias HoldContinuation = UnsafeContinuation<Void, Never>
    
    enum RunRole {
      case fetch(SharedIterator)
      case wait
      case yield(RunOutput)
      case hold
    }
    
    struct RunOutput {
      let value: Result<Element?, Error>
      var shouldCancel = false
    }
    
    enum Connection {
      case active(id: UInt, prefix: Deque<Element>)
      case terminal
    }
    
    private enum IterationPhase {
      case pending
      case fetching
      case done(Result<Element?, Error>)
    }
    
    private struct Runner {
      var iterationIndex: Int
      var active = false
      var cancelled = false
    }
    
    private struct RunContinuation {
      
      var held: [HoldContinuation]?
      var waiting: [(WaitContinuation, RunOutput)]?
      
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
    
    struct SharedIterator: Sendable {
      
      private let task: Task<Void, Never>
      private let relay: AsyncRelay<Result<Element?, Error>>
      
      init(_ base: Base) {
        let relay =  AsyncRelay<Result<Element?, Error>>()
        let operation = { @Sendable /* @MainActor */ in
          await withTaskCancellationHandler {
            var iterator = base.makeAsyncIterator()
            while let send = await relay.sendHandler() {
              let result: Result<Element?, Error>
              do {
                result = .success(try await iterator.next())
              }
              catch {
                result = .failure(error)
              }
              send(result)
              if (try? result.get()) == nil { break }
            }
          } onCancel: {
            relay.cancel()
          }
        }
        self.relay = relay
        self.task = Task(operation: operation)
      }
      
      func next() async -> Result<Element?, Error> {
        await relay.next() ?? .success(nil)
      }
      
      func cancel() {
        relay.cancel()
      }
    }
    
    private struct State: Sendable {
      
      let base: Base
      let replayCount: Int
      let iteratorDisposalPolicy: IteratorDisposalPolicy
      var baseIterator: SharedIterator?
      var nextRunnerID = (UInt.min + 1)
      var currentIterationIndex = 0
      var nextIterationIndex: Int { (currentIterationIndex + 1) % 2 }
      var history = Deque<Element>()
      var runners = [UInt: Runner]()
      var heldRunnerContinuations = [UnsafeContinuation<Void, Never>]()
      var waitingRunnerContinuations = [UInt: WaitContinuation]()
      var phase = IterationPhase.pending
      var terminal = false
      
      init(
        _ base: Base,
        replayCount: Int,
        iteratorDisposalPolicy: IteratorDisposalPolicy
      ) {
        precondition(replayCount >= 0, "history must be greater than or equal to zero")
        self.base = base
        self.baseIterator = SharedIterator(base)
        self.replayCount = replayCount
        self.iteratorDisposalPolicy = iteratorDisposalPolicy
      }
      
      mutating func establish() -> (Connection, RunContinuation?) {
        guard terminal == false else { return (.terminal, nil) }
        defer { nextRunnerID += 1}
        let iterationIndex: Int
        if case .done(_) = phase {
          iterationIndex = nextIterationIndex
        } else {
          iterationIndex = currentIterationIndex
        }
        runners[nextRunnerID] = Runner(iterationIndex: iterationIndex)
        let connection = Connection.active(id: nextRunnerID, prefix: history)
        let continuation = RunContinuation(held: finalizeIterationIfNeeded())
        return (connection, continuation)
      }
      
      mutating func run(
        _ runnerID: UInt
      ) -> (RunRole, RunContinuation?) {
        guard var runner = runners[runnerID], runner.cancelled == false else {
          let output = RunOutput(value: .success(nil), shouldCancel: true)
          return (.yield(output), nil)
        }
        if runner.iterationIndex == currentIterationIndex {
          runner.active = true
          runners[runnerID] = runner
          switch phase {
          case .pending:
            guard let baseIterator else { preconditionFailure("run started out of band") }
            phase = .fetching
            return (.fetch(baseIterator), nil)
          case .fetching:
            return (.wait, nil)
          case .done(let result):
            finish(runnerID)
            let shouldCancel = terminal || runner.cancelled
            let role = RunRole.yield(RunOutput(value: result, shouldCancel: shouldCancel))
            return (role, .init(held: finalizeIterationIfNeeded()))
          }
        }
        else {
          return (.hold, nil)
        }
      }
      
      mutating func fetch(
        _ runnerID: UInt, resumedWithResult result: Result<Element?, Error>
      ) -> (RunOutput, RunContinuation) {
        guard let runner = runners[runnerID] else {
          preconditionFailure("fetching runner resumed out of band")
        }
        self.terminal = self.terminal || ((try? result.get()) == nil)
        self.phase = .done(result)
        finish(runnerID)
        updateHistory(withResult: result)
        var continuation = gatherWaitingRunnerContinuationsForResumption(withResult: result)
        continuation.held = finalizeIterationIfNeeded()
        let ouput = RunOutput(value: result, shouldCancel: runner.cancelled)
        return (ouput, continuation)
      }
      
      mutating func wait(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: WaitContinuation
      ) -> RunContinuation? {
        switch phase {
        case .fetching:
          waitingRunnerContinuations[runnerID] = continuation
          return nil
        case .done(let result):
          guard let runner = runners[runnerID] else {
            preconditionFailure("waiting runner resumed out of band")
          }
          finish(runnerID)
          let shouldCancel = terminal || runner.cancelled
          let output = RunOutput(value: result, shouldCancel: shouldCancel)
          let continuation = RunContinuation(
            held: finalizeIterationIfNeeded(),
            waiting: [(continuation, output)]
          )
          return continuation
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
            let shouldCancel = terminal || waitingRunner.cancelled
            let output = RunOutput(value: result, shouldCancel: shouldCancel)
            return (continuation, output)
          }
        waitingRunnerContinuations.removeAll()
        return .init(waiting: continuationPairs)
      }
      
      mutating func hold(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: HoldContinuation
      ) -> RunContinuation? {
        guard let runner = runners[runnerID], runner.iterationIndex == nextIterationIndex else {
          return RunContinuation(held: [continuation])
        }
        heldRunnerContinuations.append(continuation)
        return nil
      }
      
      private mutating func finish(_ runnerID: UInt) {
        guard var runner = runners.removeValue(forKey: runnerID) else {
          preconditionFailure("run finished out of band")
        }
        if terminal == false, runner.cancelled == false {
          runner.active = false
          runner.iterationIndex = nextIterationIndex
          runners[runnerID] = runner
        }
      }
      
      mutating func cancel(_ runnerID: UInt) -> RunContinuation? {
        if let runner = runners.removeValue(forKey: runnerID), runner.active {
          runners[runnerID] = .init(
            iterationIndex: runner.iterationIndex, active: true, cancelled: true)
          return nil
        }
        else {
          return RunContinuation(held: finalizeIterationIfNeeded())
        }
      }
      
      mutating func abort() -> RunContinuation {
        terminal = true
        runners = runners.filter { _, runner in runner.active }
        return RunContinuation(held: finalizeIterationIfNeeded())
      }
      
      private mutating func finalizeIterationIfNeeded() -> [HoldContinuation]? {
        let isCurrentIterationActive = runners.values.contains { runner in
          runner.iterationIndex == currentIterationIndex
        }
        if isCurrentIterationActive { return nil }
        if terminal {
          self.phase = .done(.success(nil))
          self.baseIterator?.cancel()
          self.baseIterator = nil
          self.history.removeAll()
        }
        else {
          self.currentIterationIndex = nextIterationIndex
          self.phase = .pending
          if runners.isEmpty && iteratorDisposalPolicy == .whenTerminatedOrVacant {
            self.baseIterator?.cancel()
            self.baseIterator = SharedIterator(base)
            self.history.removeAll()
          }
        }
        let continuations = heldRunnerContinuations
        heldRunnerContinuations.removeAll()
        return continuations
      }
      
      private mutating func updateHistory(withResult result: Result<Element?, Error>) {
        guard replayCount > 0, case .success(let element?) = result else {
          return
        }
        if history.count >= replayCount {
          history.removeFirst()
        }
        history.append(element)
      }
    }
    
    private let state: ManagedCriticalState<State>
    
    init(_ base: Base, replayCount: Int, iteratorDisposalPolicy: IteratorDisposalPolicy) {
      self.state = .init(
        State(base, replayCount: replayCount, iteratorDisposalPolicy: iteratorDisposalPolicy)
      )
    }
    
    func establish() -> Connection {
      let (connection, continuation) = state.withCriticalRegion {
        state in state.establish()
      }
      continuation?.resume()
      return connection
    }
    
    func startRun(_ runnerID: UInt) -> RunRole {
      let (role, continuation) = state.withCriticalRegion {
        state in state.run(runnerID)
      }
      continuation?.resume()
      return role
    }
    
    func fetch(_ runnerID: UInt, resumedWithResult result: Result<Element?, Error>) -> RunOutput {
      let (output, continuation) = state.withCriticalRegion { state in
        state.fetch(runnerID, resumedWithResult: result)
      }
      continuation.resume()
      return output
    }
    
    func wait(_ runnerID: UInt) async -> RunOutput {
      await withUnsafeContinuation { continuation in
        let continuation = state.withCriticalRegion { state in
          state.wait(runnerID, suspendedWithContinuation: continuation)
        }
        continuation?.resume()
      }
    }
    
    func hold(_ runnerID: UInt) async {
      await withUnsafeContinuation { continuation in
        let continuation = state.withCriticalRegion { state in
          state.hold(runnerID, suspendedWithContinuation: continuation)
        }
        continuation?.resume()
      }
    }
    
    func cancel(_ runnerID: UInt) {
      let continuation = state.withCriticalRegion { state in
        state.cancel(runnerID)
      }
      continuation?.resume()
    }
    
    func abort() {
      let continuation = state.withCriticalRegion { state in
        state.abort()
      }
      continuation.resume()
    }
  }
}

// MARK: - Utilities

/// A utility to perform deallocation tasks on value types
fileprivate final class DeallocToken: Sendable {
  let action: @Sendable () -> Void
  init(_ dealloc: @escaping @Sendable () -> Void) {
    self.action = dealloc
  }
  deinit { action() }
}

/// An asynchronous primitive that synchronizes sending elements between Tasks
fileprivate struct AsyncRelay<Element: Sendable>: Sendable {
  
  private enum State {
    
    case idle
    case pendingRequest(UnsafeContinuation<(@Sendable (Element) -> Void)?, Never>)
    case pendingResponse(UnsafeContinuation<Element?, Never>)
    case terminal
    
    mutating func sendHandler(
      continuation: UnsafeContinuation<(@Sendable (Element) -> Void)?, Never>
    ) -> (() -> Void)? {
      switch self {
      case .idle:
        self = .pendingRequest(continuation)
      case .pendingResponse(let receiveContinuation):
        self = .idle
        return {
          continuation.resume { element in
            receiveContinuation.resume(returning: element)
          }
        }
      case .pendingRequest(_):
        fatalError("attempt to await requestHandler() on more than one task")
      case .terminal:
        return { continuation.resume(returning: nil) }
      }
      return nil
    }
    
    mutating func next(continuation: UnsafeContinuation<Element?, Never>) -> (() -> Void)? {
      switch self {
      case .idle:
        self = .pendingResponse(continuation)
      case .pendingResponse(_):
        fatalError("attempt to await next(_:) on more than one task")
      case .pendingRequest(let sendContinuation):
        self = .idle
        return {
          sendContinuation.resume { element in
            continuation.resume(returning: element)
          }
        }
      case .terminal:
        return { continuation.resume(returning: nil) }
      }
      return nil
    }
    
    mutating func cancel() -> (() -> Void)? {
      switch self {
      case .idle:
        self = .terminal
      case .pendingResponse(let receiveContinuation):
        self = .terminal
        return { receiveContinuation.resume(returning: nil) }
      case .pendingRequest(let sendContinuation):
        self = .terminal
        return { sendContinuation.resume(returning: nil) }
      case .terminal: break
      }
      return nil
    }
  }
  
  private let state = ManagedCriticalState(State.idle)
  
  init() {}
  
  func sendHandler() async -> (@Sendable (Element) -> Void)? {
    await withUnsafeContinuation { continuation in
      let resume = state.withCriticalRegion { state in
        state.sendHandler(continuation: continuation)
      }
      resume?()
    }
  }
  
  func next() async -> Element? {
    await withUnsafeContinuation { continuation in
      let resume = state.withCriticalRegion { state in
        state.next(continuation: continuation)
      }
      resume?()
    }
  }
  
  func cancel() {
    let resume = state.withCriticalRegion { state in
      state.cancel()
    }
    resume?()
  }
}

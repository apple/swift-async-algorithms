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
// The idea behind the `AsyncBroadcastSequence` algorithm is as follows: Vended
// iterators of `AsyncBroadcastSequence` are known as 'runners'. Runners compete
// in a race to grab the next element from a base iterator for each of its
// iteration cycles. The 'winner' of an iteration cycle returns the element to
// the shared context which then supplies the result to later finishers. Once
// every runner has finished, the current cycle completes and the next
// iteration can start. This means that runners move forward in lock-step, only
// proceeding when the the last runner in the current iteration has received a
// value or has cancelled.
//
// `AsyncBroadcastSequence` ITERATOR LIFECYCLE:
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
  
  /// Creates an asynchronous sequence that can be broadcast to multiple
  /// consumers.
  ///
  /// - parameter history: the number of previously emitted elements to prefix
  ///   to the iterator of a new consumer
  /// - parameter iteratorDisposalPolicy:the iterator disposal policy applied by
  ///   a asynchronous broadcast sequence to its upstream iterator
  public func broadcast(
    history historyCount: Int = 0,
    disposingBaseIterator iteratorDisposalPolicy: AsyncBroadcastSequence<Self>.IteratorDisposalPolicy = .whenTerminatedOrVacant
  ) -> AsyncBroadcastSequence<Self> {
    AsyncBroadcastSequence(
      self, history: historyCount, disposingBaseIterator: iteratorDisposalPolicy)
  }
}

// MARK: - Sequence

/// An asynchronous sequence that can be iterated by multiple concurrent
/// consumers.
///
/// Use an asynchronous broadcast sequence when you have multiple downstream
/// asynchronous sequences with which you wish to share the output of a single
/// asynchronous sequence. This can be useful if you have expensive upstream
/// operations, or if your asynchronous sequence represents the output of a
/// physical device.
///
/// Elements are emitted from a asynchronous broadcast sequence at a rate that
/// does not exceed the consumption of its slowest consumer. If this kind of
/// back-pressure isn't desirable for your use-case, ``AsyncBroadcastSequence``
/// can be composed with buffers – either upstream, downstream, or both – to
/// acheive the desired behavior.
///
/// If you have an asynchronous sequence that consumes expensive system
/// resources, it is possible to configure ``AsyncBroadcastSequence`` to discard
/// its upstream iterator when the connected downstream consumer count falls to
/// zero. This allows any cancellation tasks configured on the upstream
/// asynchronous sequence to be initiated and for expensive resources to be
/// terminated. ``AsyncBroadcastSequence`` will re-create a fresh iterator if
/// there is further demand.
///
/// For use-cases where it is important for consumers to have a record of
/// elements emitted prior to their connection, a ``AsyncBroadcastSequence`` can
/// also be configured to prefix its output with the most recently emitted
/// elements. If ``AsyncBroadcastSequence`` is configured to drop its iterator
/// when the connected consumer count falls to zero, its history will be
/// discarded at the same time.
public struct AsyncBroadcastSequence<Base: AsyncSequence> : Sendable
  where Base: Sendable, Base.Element: Sendable {
  
  /// The iterator disposal policy applied by a asynchronous broadcast sequence to
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
  
  /// Contructs a asynchronous broadcast sequence
  ///
  /// - parameter base: the asynchronous sequence to be broadcast
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

extension AsyncBroadcastSequence: AsyncSequence {
  
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
            do {
              let element = try await iterator.next()
              context.fetch(id, resumedWithResult: .success(element))
              return try processOutput(.success(element))
            }
            catch {
              context.fetch(id, resumedWithResult: .failure(error))
              return try processOutput(.failure(error))
            }
          case .wait:
            let output = await context.wait(id)
            return try processOutput(output)
          case .yield(let output, let resume):
            resume?()
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
      _ output: Result<Element?, Error>
    ) rethrows -> Element? {
      switch output {
      case .success(let value?):
        return value
      default:
        self.context = nil
        return try output._rethrowGet()
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(context)
  }
}

// MARK: - Context

private extension AsyncBroadcastSequence {
  
  struct Context: Sendable {
    
    typealias WaitContinuation = UnsafeContinuation<Result<Element?, Error>, Never>
    typealias HoldContinuation = UnsafeContinuation<Void, Never>
    
    enum RunRole {
      case fetch(SharedIterator<Base>)
      case wait
      case yield(Result<Element?, Error>, (() -> Void)?)
      case hold
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
    
    private struct State: Sendable {
      
      let base: Base
      let replayCount: Int
      let iteratorDisposalPolicy: IteratorDisposalPolicy
      var iterator: SharedIterator<Base>?
      var nextRunnerID = (UInt.min + 1)
      var currentIterationIndex = 0
      var nextIterationIndex: Int { (currentIterationIndex + 1) % 2 }
      var history = Deque<Element>()
      var runners = [UInt: Runner]()
      var iterationPhase = IterationPhase.pending
      var terminal = false
      var heldRunnerContinuations = [UnsafeContinuation<Void, Never>]()
      var waitingRunnerContinuations = [UInt: WaitContinuation]()
      
      init(
        _ base: Base,
        replayCount: Int,
        iteratorDisposalPolicy: IteratorDisposalPolicy
      ) {
        precondition(replayCount >= 0, "history must be greater than or equal to zero")
        self.base = base
        self.replayCount = replayCount
        self.iteratorDisposalPolicy = iteratorDisposalPolicy
      }
      
      mutating func establish() -> (Connection, (() -> Void)?) {
        guard terminal == false else { return (.terminal, nil) }
        defer { nextRunnerID += 1}
        let iterationIndex: Int
        if case .done(_) = iterationPhase {
          iterationIndex = nextIterationIndex
        } else {
          iterationIndex = currentIterationIndex
        }
        runners[nextRunnerID] = Runner(iterationIndex: iterationIndex)
        let connection = Connection.active(id: nextRunnerID, prefix: history)
        return (connection, finalizeIterationIfNeeded())
      }
      
      mutating func run(
        _ runnerID: UInt
      ) -> RunRole {
        guard var runner = runners[runnerID], runner.cancelled == false else {
          return .yield(.success(nil), nil)
        }
        if runner.iterationIndex == currentIterationIndex {
          runner.active = true
          runners[runnerID] = runner
          switch iterationPhase {
          case .pending:
            iterationPhase = .fetching
            return .fetch(sharedIterator())
          case .fetching:
            return .wait
          case .done(let result):
            finish(runnerID)
            return .yield(result, finalizeIterationIfNeeded())
          }
        }
        else {
          return .hold
        }
      }
      
      mutating func fetch(
        _ runnerID: UInt, resumedWithResult result: Result<Element?, Error>
      ) -> (() -> Void)? {
        self.terminal = self.terminal || ((try? result.get()) == nil)
        self.iterationPhase = .done(result)
        finish(runnerID)
        updateHistory(withResult: result)
        let waitContinuation = gatherWaitingRunnerContinuationsForResumption(withResult: result)
        let heldContinuation = finalizeIterationIfNeeded()
        return {
          waitContinuation?()
          heldContinuation?()
        }
      }
      
      mutating func wait(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: WaitContinuation
      ) -> (() -> Void)? {
        switch iterationPhase {
        case .fetching:
          waitingRunnerContinuations[runnerID] = continuation
          return nil
        case .done(let result):
          finish(runnerID)
          let waitContinuation = { continuation.resume(returning: result) }
          let heldContinuation = finalizeIterationIfNeeded()
          return {
            waitContinuation()
            heldContinuation?()
          }
        default:
          preconditionFailure("waiting runner suspended out of band")
        }
      }
      
      private mutating func gatherWaitingRunnerContinuationsForResumption(
        withResult result: Result<Element?, Error>
      ) -> (() -> Void)? {
        let continuations = waitingRunnerContinuations
          .map { waitingRunnerID, continuation in
            finish(waitingRunnerID)
            return { continuation.resume(returning: result) }
          }
        waitingRunnerContinuations.removeAll()
        return {
          for continuation in continuations { continuation() }
        }
      }
      
      mutating func hold(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: HoldContinuation
      ) -> (() -> Void)? {
        guard let runner = runners[runnerID], runner.iterationIndex == nextIterationIndex else {
          return continuation.resume
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
      
      mutating func cancel(_ runnerID: UInt) -> (() -> Void)? {
        if let runner = runners.removeValue(forKey: runnerID), runner.active {
          runners[runnerID] = .init(
            iterationIndex: runner.iterationIndex, active: true, cancelled: true)
          return nil
        }
        else {
          return finalizeIterationIfNeeded()
        }
      }
      
      mutating func abort() -> (() -> Void)? {
        terminal = true
        runners = runners.filter { _, runner in runner.active }
        return finalizeIterationIfNeeded()
      }
      
      private mutating func finalizeIterationIfNeeded() -> (() -> Void)? {
        let isCurrentIterationActive = runners.values.contains { runner in
          runner.iterationIndex == currentIterationIndex
        }
        if isCurrentIterationActive { return nil }
        if terminal {
          self.iterationPhase = .done(.success(nil))
          self.iterator = nil
          self.history.removeAll()
        }
        else {
          self.currentIterationIndex = nextIterationIndex
          self.iterationPhase = .pending
          if runners.isEmpty && iteratorDisposalPolicy == .whenTerminatedOrVacant {
            self.iterator = nil
            self.history.removeAll()
          }
        }
        let continuations = heldRunnerContinuations
        heldRunnerContinuations.removeAll()
        return {
          for continuation in continuations { continuation.resume() }
        }
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
      
      private mutating func sharedIterator() -> SharedIterator<Base> {
        guard let iterator else {
          let iterator = SharedIterator(base)
          self.iterator = iterator
          return iterator
        }
        return iterator
      }
    }
    
    private let state: ManagedCriticalState<State>
    
    init(_ base: Base, replayCount: Int, iteratorDisposalPolicy: IteratorDisposalPolicy) {
      self.state = .init(
        State(base, replayCount: replayCount, iteratorDisposalPolicy: iteratorDisposalPolicy)
      )
    }
    
    func establish() -> Connection {
      let (connection, resume) = state.withCriticalRegion {
        state in state.establish()
      }
      resume?()
      return connection
    }
    
    func startRun(_ runnerID: UInt) -> RunRole {
      return state.withCriticalRegion {
        state in state.run(runnerID)
      }
    }
    
    func fetch(_ runnerID: UInt, resumedWithResult result: Result<Element?, Error>) {
      let resume = state.withCriticalRegion { state in
        state.fetch(runnerID, resumedWithResult: result)
      }
      resume?()
    }
    
    func wait(_ runnerID: UInt) async -> Result<Element?, Error> {
      await withUnsafeContinuation { continuation in
        let resume = state.withCriticalRegion { state in
          state.wait(runnerID, suspendedWithContinuation: continuation)
        }
        resume?()
      }
    }
    
    func hold(_ runnerID: UInt) async {
      await withUnsafeContinuation { continuation in
        let resume = state.withCriticalRegion { state in
          state.hold(runnerID, suspendedWithContinuation: continuation)
        }
        resume?()
      }
    }
    
    func cancel(_ runnerID: UInt) {
      let resume = state.withCriticalRegion { state in
        state.cancel(runnerID)
      }
      resume?()
    }
    
    func abort() {
      let resume = state.withCriticalRegion { state in
        state.abort()
      }
      resume?()
    }
  }
}

// MARK: - Shared Iterator

fileprivate final class SharedIterator<Base: AsyncSequence>
  where Base: Sendable, Base.Element: Sendable {
  
  private struct Relay<Element: Sendable>: Sendable {
    
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
  
  typealias Element = Base.Element

  private let relay: Relay<Result<Element?, Error>>
  private let task: Task<Void, Never>

  init(_ base: Base) {
    let relay = Relay<Result<Element?, Error>>()
    let task = Task.detached(priority: .high) {
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
        let terminal = (try? result.get()) == nil
        if terminal {
          relay.cancel()
          break
        }
      }
    }
    self.relay = relay
    self.task = task
  }
  
  deinit {
    relay.cancel()
  }

  public func next() async rethrows -> Element? {
    guard Task.isCancelled == false else { return nil }
    let result = await relay.next() ?? .success(nil)
    return try result._rethrowGet()
  }
}

extension SharedIterator: AsyncIteratorProtocol, Sendable {}

// MARK: - Utilities

/// A utility to perform deallocation tasks on value types
fileprivate final class DeallocToken: Sendable {
  let action: @Sendable () -> Void
  init(_ dealloc: @escaping @Sendable () -> Void) {
    self.action = dealloc
  }
  deinit { action() }
}

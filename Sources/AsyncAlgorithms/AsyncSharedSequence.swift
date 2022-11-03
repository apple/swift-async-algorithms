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

extension AsyncSequence where Self: Sendable, Element: Sendable {
  
  /// Creates an asynchronous sequence that can be shared by multiple consumers.
  ///
  /// - parameter history: the number of previously emitted elements to prefix to the iterator of a new
  ///   consumer
  /// - parameter iteratorDisposalPolicy:the iterator disposal policy applied by a shared
  ///   asynchronous sequence to its upstream iterator
  public func share(
    history historyCount: Int = 0,
    disposingBaseIterator iteratorDisposalPolicy: AsyncSharedSequence<Self>.IteratorDisposalPolicy = .whenTerminatedOrVacant
  ) -> AsyncSharedSequence<Self> {
    AsyncSharedSequence(
      self, history: historyCount, disposingBaseIterator: iteratorDisposalPolicy)
  }
}

// MARK: - Sequence

/// An asynchronous sequence that can be iterated by multiple concurrent consumers.
///
/// Use a shared asynchronous sequence when you have multiple downstream asynchronous sequences
/// with which you wish to share the output of a single asynchronous sequence. This can be useful if
/// you have expensive upstream operations, or if your asynchronous sequence represents the output
/// of a physical device.
///
/// Elements are emitted from a shared asynchronous sequence at a rate that does not exceed the
/// consumption of its slowest consumer. If this kind of back-pressure isn't desirable for your
/// use-case, ``AsyncSharedSequence`` can be composed with buffers – either upstream, downstream,
/// or both – to acheive the desired behavior.
///
/// If you have an asynchronous sequence that consumes expensive system resources, it is possible to
/// configure ``AsyncSharedSequence`` to discard its upstream iterator when the connected
/// downstream consumer count falls to zero. This allows any cancellation tasks configured on the
/// upstream asynchronous sequence to be initiated and for expensive resources to be terminated.
/// ``AsyncSharedSequence`` will re-create a fresh iterator if there is further demand.
///
/// For use-cases where it is important for consumers to have a record of elements emitted prior to
/// their connection, a ``AsyncSharedSequence`` can also be configured to prefix its output with
/// the most recently emitted elements. If ``AsyncSharedSequence`` is configured to drop its
/// iterator when the connected consumer count falls to zero, its history will be discarded at the
/// same time.
public struct AsyncSharedSequence<Base: AsyncSequence>
  where Base: Sendable, Base.Element: Sendable {
  
  /// The iterator disposal policy applied by a shared asynchronous sequence to its upstream iterator
  ///
  /// - note: the iterator is always disposed when the base asynchronous sequence terminates
  public enum IteratorDisposalPolicy: Sendable {
    /// retains the upstream iterator for use by future consumers until the base asynchronous
    /// sequence is terminated
    case whenTerminated
    /// discards the upstream iterator when the number of consumers falls to zero or the base
    /// asynchronous sequence is terminated
    case whenTerminatedOrVacant
  }
  
  private let base: Base
  private let state: State
  private let deallocToken: DeallocToken
  
  /// Contructs a shared asynchronous sequence
  ///
  /// - parameter base: the asynchronous sequence to be shared
  /// - parameter history: the number of previously emitted elements to prefix to the iterator of a
  ///   new consumer
  /// - parameter iteratorDisposalPolicy: the iterator disposal policy applied to the upstream
  ///   iterator
  public init(
    _ base: Base,
    history historyCount: Int = 0,
    disposingBaseIterator iteratorDisposalPolicy: IteratorDisposalPolicy = .whenTerminatedOrVacant
  ) {
    let state = State(base, replayCount: historyCount, discardsIterator: iteratorDisposalPolicy)
    self.base = base
    self.state = state
    self.deallocToken = .init { state.abort() }
  }
}

// MARK: - Iterator

extension AsyncSharedSequence: AsyncSequence, Sendable {
  
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol, Sendable where Base.Element: Sendable {
    
    private let id: UInt
    private let deallocToken: DeallocToken?
    private var prefix: Deque<Element>
    private var state: State?
    
    fileprivate init(_ state: State) {
      switch state.establish() {
      case .active(let id, let prefix, let continuation):
        self.id = id
        self.prefix = prefix
        self.deallocToken = .init { state.cancel(id) }
        self.state = state
        continuation?.resume()
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
          let command = state.run(id)
          switch command {
          case .fetch(let iterator):
            let upstreamResult = await iterator.next()
            let output = state.fetch(id, resumedWithResult: upstreamResult, iterator: iterator)
            return try processOutput(output)
          case .wait:
            let output = await withUnsafeContinuation { continuation in
              let immediateOutput = state.wait(id, suspendedWithContinuation: continuation)
              if let immediateOutput { continuation.resume(returning: immediateOutput) }
            }
            return try processOutput(output)
          case .yield(let output):
            return try processOutput(output)
          case .hold:
            await withUnsafeContinuation { continuation in
              let shouldImmediatelyResume = state.hold(id, suspendedWithContinuation: continuation)
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
    
    private mutating func processOutput(_ output: RunOutput) rethrows -> Element? {
      output.continuation?.resume()
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
  
  final class DeallocToken: Sendable {
    let action: @Sendable () -> Void
    init(_ dealloc: @escaping @Sendable () -> Void) {
      self.action = dealloc
    }
    deinit { action() }
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
  
  struct Runner {
    let id: UInt
    var group: RunGroup
    var isCancelled = false
    var isRunning = false
  }
  
  enum Connection {
    case active(id: UInt, prefix: Deque<Element>, continuation: RunContinuation?)
    case terminal(id: UInt)
  }
  
  enum Command {
    case fetch(SharedUpstreamIterator)
    case wait
    case yield(RunOutput)
    case hold
  }
  
  enum RunGroup {
    case a
    case b
    var nextGroup: RunGroup { self == .a ? .b : .a }
    mutating func flip() { self = nextGroup }
  }
  
  struct RunOutput {
    let value: Result<Element?, Error>
    var shouldCancel = false
    var continuation: RunContinuation?
  }
  
  struct RunContinuation {
    var held: [UnsafeContinuation<Void, Never>]?
    var waiting: [(UnsafeContinuation<RunOutput, Never>, RunOutput)]?
    func resume() {
      if let held {
        for continuation in held { continuation.resume() }
      }
      if let waiting {
        for (continuation, output) in waiting { continuation.resume(returning: output) }
      }
    }
  }
  
  enum Phase {
    case pending
    case fetching
    case done(Result<Element?, Error>)
  }
  
  struct State: Sendable {
    
    private struct Storage: Sendable {
      
      let base: Base
      let replayCount: Int
      let iteratorDiscardPolicy: IteratorDisposalPolicy
      var iterator: SharedUpstreamIterator?
      var nextRunnerID = UInt.min
      var runners = [UInt: Runner]()
      var phase = Phase.pending
      var currentGroup = RunGroup.a
      var history = Deque<Element>()
      var heldRunnerContinuations = [UnsafeContinuation<Void, Never>]()
      var waitingRunnerContinuations = [UInt: UnsafeContinuation<RunOutput, Never>]()
      var terminal = false
      var hasActiveOrPendingRunnersInCurrentGroup: Bool {
        runners.values.contains { $0.group == currentGroup }
      }
      
      init(_ base: Base, replayCount: Int, discardsIterator: IteratorDisposalPolicy) {
        precondition(replayCount >= 0, "history must be greater than or equal to zero")
        self.base = base
        self.replayCount = replayCount
        self.iteratorDiscardPolicy = discardsIterator
        self.iterator = .init(base)
      }
      
      mutating func establish() -> Connection {
        defer { nextRunnerID += 1}
        if terminal {
          return .terminal(id: nextRunnerID)
        }
        else {
          let group: RunGroup
          if case .done(_) = phase {
            group = currentGroup.nextGroup
          } else {
            group = currentGroup
          }
          let runner = Runner(id: nextRunnerID, group: group)
          runners[nextRunnerID] = runner
          let continuation = RunContinuation(held: finalizeRunGroupIfNeeded())
          return .active(id: nextRunnerID, prefix: history, continuation: continuation)
        }
      }
      
      mutating func run(_ runnerID: UInt) -> Command {
        guard terminal == false, var runner = runners[runnerID] else {
          if case .done(let result) = phase {
            return .yield(RunOutput(value: result, shouldCancel: true))
          }
          return .yield(RunOutput(value: .success(nil), shouldCancel: true))
        }
        runner.isRunning = true
        runners.updateValue(runner, forKey: runnerID)
        guard runner.group == currentGroup else { return .hold }
        switch phase {
        case .pending:
          phase = .fetching
          guard let iterator = iterator else {
            preconditionFailure("iterator must not be over-borrowed")
          }
          self.iterator = nil
          return .fetch(iterator)
        case .fetching:
          return .wait
        case .done(let result):
          finish(runnerID)
          return .yield(
            RunOutput(
              value: result,
              shouldCancel: runner.isCancelled,
              continuation: .init(held: finalizeRunGroupIfNeeded())
            )
          )
        }
      }
      
      mutating func fetch(
        _ runnerID: UInt,
        resumedWithResult result: Result<Element?, Error>,
        iterator: SharedUpstreamIterator
      ) -> RunOutput {
        guard let runner = runners[runnerID] else {
          preconditionFailure("fetching runner resumed out of band")
        }
        guard case .fetching = phase, case currentGroup = runner.group else {
          preconditionFailure("fetching runner resumed out of band")
        }
        guard self.iterator == nil else {
          preconditionFailure("iterator is already in place")
        }
        self.iterator = iterator
        phase = .done(result)
        terminal = (try? result.get()) == nil
        finish(runnerID)
        updateHistory(withResult: result)
        let continuationPairs = waitingRunnerContinuations.map { waitingRunnerID, continuation in
          guard let waitingRunner = runners[waitingRunnerID] else {
            preconditionFailure("fetching runner resumed out of band")
          }
          finish(waitingRunnerID)
          return (continuation, RunOutput(value: result, shouldCancel: waitingRunner.isCancelled))
        }
        waitingRunnerContinuations.removeAll()
        return RunOutput(
          value: result,
          shouldCancel: runner.isCancelled,
          continuation: .init(held: finalizeRunGroupIfNeeded(), waiting: continuationPairs)
        )
      }
      
      mutating func wait(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: UnsafeContinuation<RunOutput, Never>
      ) -> RunOutput? {
        guard let runner = runners[runnerID] else {
          preconditionFailure("waiting runner resumed out of band")
        }
        switch phase {
        case .fetching:
          waitingRunnerContinuations[runnerID] = continuation
          return nil
        case .done(let result):
          finish(runnerID)
          return RunOutput(
            value: result,
            shouldCancel: runner.isCancelled,
            continuation: .init(held: finalizeRunGroupIfNeeded())
          )
        default:
          preconditionFailure("waiting runner resumed out of band")
        }
      }
      
      mutating func hold(
        _ runnerID: UInt,
        suspendedWithContinuation continuation: UnsafeContinuation<Void, Never>
      ) -> Bool {
        guard let runner = runners[runnerID] else {
          preconditionFailure("held runner resumed out of band")
        }
        if currentGroup == runner.group {
          return true
        }
        else {
          heldRunnerContinuations.append(continuation)
          return false
        }
      }
      
      private mutating func finish(_ runnerID: UInt) {
        guard var runner = runners[runnerID] else { return }
        if runner.isCancelled {
          runners.removeValue(forKey: runnerID)
        }
        else {
          runner.isRunning = false
          runner.group.flip()
          runners[runnerID] = runner
        }
      }
      
      mutating func cancel(_ runnerID: UInt) -> [UnsafeContinuation<Void, Never>]? {
        if var runner = runners[runnerID] {
          if runner.isRunning {
            runner.isCancelled = true
            runners[runnerID] = runner
          }
          else {
            runners.removeValue(forKey: runnerID)
            return finalizeRunGroupIfNeeded()
          }
        }
        return nil
      }
      
      mutating func abort() -> [UnsafeContinuation<Void, Never>]? {
        terminal = true
        runners = runners.compactMapValues { $0.isRunning ? $0 : nil }
        return finalizeRunGroupIfNeeded()
      }
      
      private mutating func finalizeRunGroupIfNeeded() -> [UnsafeContinuation<Void, Never>]? {
        if hasActiveOrPendingRunnersInCurrentGroup { return nil }
        if terminal {
          self.iterator = nil
          self.phase = .done(.success(nil))
          self.history.removeAll()
        }
        else {
          self.currentGroup.flip()
          self.phase = .pending
          if runners.isEmpty && iteratorDiscardPolicy == .whenTerminatedOrVacant {
            self.iterator = SharedUpstreamIterator(base)
            self.history.removeAll()
          }
        }
        let continuations = self.heldRunnerContinuations
        self.heldRunnerContinuations.removeAll()
        return continuations
      }
      
      private mutating func updateHistory(withResult result: Result<Element?, Error>) {
        guard replayCount > 0, case .success(let element?) = result else { return }
        if history.count >= replayCount {
          history.removeFirst()
        }
        history.append(element)
      }
    }
    
    private let storage: ManagedCriticalState<Storage>
    
    init(_ base: Base, replayCount: Int, discardsIterator: IteratorDisposalPolicy) {
      self.storage = .init(
        Storage(base, replayCount: replayCount, discardsIterator: discardsIterator)
      )
    }
    
    func establish() -> Connection {
      storage.withCriticalRegion { $0.establish() }
    }
    
    func run(_ runnerID: UInt) -> Command {
      storage.withCriticalRegion { $0.run(runnerID) }
    }
    
    func fetch(
      _ runnerID: UInt,
      resumedWithResult result: Result<Element?, Error>,
      iterator: SharedUpstreamIterator
    ) -> RunOutput {
      storage.withCriticalRegion { state in
        state.fetch(runnerID, resumedWithResult: result, iterator: iterator)
      }
    }
    
    func wait(
      _ runnerID: UInt,
      suspendedWithContinuation continuation: UnsafeContinuation<RunOutput, Never>
    ) -> RunOutput? {
      storage.withCriticalRegion { state in
        state.wait(runnerID, suspendedWithContinuation: continuation)
      }
    }
    
    func hold(
      _ runnerID: UInt,
      suspendedWithContinuation continuation: UnsafeContinuation<Void, Never>
    ) -> Bool {
      storage.withCriticalRegion { state in
        state.hold(runnerID, suspendedWithContinuation: continuation)
      }
    }
    
    func cancel(_ runnerID: UInt) {
      let continuations = storage.withCriticalRegion { $0.cancel(runnerID) }
      if let continuations {
        for continuation in continuations {
          continuation.resume()
        }
      }
    }
    
    func abort() {
      let continuations = storage.withCriticalRegion { state in state.abort() }
      if let continuations {
        for continuation in continuations {
          continuation.resume()
        }
      }
    }
  }
}

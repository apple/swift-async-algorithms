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

// MARK: - AsyncRelay

/// An asynchronous sequence generated from a closure that limits its rate of
/// element production to the rate of element consumption
///
/// ``AsyncRelaySequence`` conforms to ``AsyncSequence``, providing a convenient
/// way to create an asynchronous sequence without manually conforming a type
/// ``AsyncSequence``.
///
/// You initialize an ``AsyncRelaySequence`` with a closure that receives an
/// ``AsyncRelay.Continuation``. Produce elements in this closure, then provide
/// them to the sequence by calling the suspending continuation. Execution will
/// resume as soon as the value produced is consumed. You call the continuation
/// instance directly because it defines a `callAsFunction()` method that Swift
/// calls when you call the instance. When there are no further elements to
/// produce, simply allow the function to exit. This causes the sequence
/// iterator to produce a nil, which terminates the sequence.
///
/// Both ``AsyncRelaySequence`` and its iterator ``AsyncRelay`` conform to
/// ``Sendable``, which permits them being called from from concurrent contexts.
public struct AsyncRelaySequence<Element: Sendable> : Sendable, AsyncSequence {
  
  public typealias AsyncIterator = AsyncRelay<Element>
  
  private let producer: AsyncIterator.Producer
  
  public init(_ producer: @escaping AsyncIterator.Producer) {
    self.producer = producer
  }
  
  public func makeAsyncIterator() -> AsyncRelay<Element> {
    .init(producer)
  }
}

/// An asynchronous sequence iterator generated from a closure that limits its
/// rate of element production to the rate of element consumption
///
/// For usage information see ``AsyncRelaySequence``.
///
/// ``AsyncRelay`` conforms to ``Sendable``, which permits calling it from
/// concurrent contexts.
public struct AsyncRelay<Element: Sendable> : Sendable, AsyncIteratorProtocol {
  
  public typealias Producer = @Sendable (Continuation) async -> Void
  
  public struct Continuation {
    
    private let context: RelayContext<Element>
    
    fileprivate init(_ context: RelayContext<Element>) {
      self.context = context
    }
    
    public func callAsFunction(_ element: Element) async {
      await context.yield(element)
    }
  }
  
  private enum TaskState {
    case pending
    case running(Task<Void, Never>)
    case terminal
  }
  
  private let taskState = ManagedCriticalState<TaskState>(.pending)
  private let context: RelayContext<Element>
  private let producer: Producer
  private let deallocToken: DeallocToken
  
  public init(_ producer: @escaping Producer) {
    self.context = .init()
    self.producer = producer
    self.deallocToken = .init { [taskState, context] in
      taskState.withCriticalRegion { taskState in
        if case .running(let task) = taskState { task.cancel() }
        taskState = .terminal
      }
      context.cancel()
    }
  }
  
  public func next() async -> Element? {
    guard Task.isCancelled == false else { return nil }
    taskState.withCriticalRegion { [producer, context] taskState in
      guard case .pending = taskState else { return }
      let task = Task {
        await producer(Continuation(context))
        context.cancel()
      }
      taskState = .running(task)
    }
    return await context.next()
  }
}

// MARK: - AsyncThrowingRelay

/// A throwing asynchronous sequence generated from a closure that limits its
/// rate of element production to the rate of element consumption
///
/// ``AsyncThrowingRelaySequence`` conforms to ``AsyncSequence``, providing a
/// convenient way to create a throwing asynchronous sequence without manually
/// conforming a type ``AsyncSequence``.
///
/// You initialize an ``AsyncThrowingRelaySequence`` with a closure that
/// receives an ``AsyncThrowingRelay.Continuation``. Produce elements in this
/// closure, then provide them to the sequence by calling the suspending
/// continuation. Execution will resume as soon as the value produced is
/// consumed. You call the continuation instance directly because it defines a
/// `callAsFunction()` method that Swift calls when you call the instance. When
/// there are no further elements to produce, simply allow the function to exit.
/// This causes the sequence to produce a nil, which terminates the sequence.
/// You may also choose to throw from within the closure which terminates the
/// sequence with an ``Error``.
///
/// Both ``AsyncThrowingRelaySequence`` and its iterator ``AsyncThrowingRelay``
/// conform to ``Sendable``, which permits them being called from from
/// concurrent contexts.
public struct AsyncThrowingRelaySequence<Element: Sendable> : Sendable, AsyncSequence {
  
  public typealias AsyncIterator = AsyncThrowingRelay<Element>
  
  private let producer: AsyncIterator.Producer
  
  public init(_ producer: @escaping AsyncIterator.Producer) {
    self.producer = producer
  }
  
  public func makeAsyncIterator() -> AsyncThrowingRelay<Element> {
    .init(producer)
  }
}

/// A throwing asynchronous sequence iterator generated from a closure that
/// limits its rate of element production to the rate of element consumption
///
/// For usage information see ``AsyncThrowingRelaySequence``.
///
/// ``AsyncThrowingRelay`` conforms to ``Sendable``, which permits calling it
/// from concurrent contexts.
public struct AsyncThrowingRelay<Element: Sendable> : Sendable, AsyncIteratorProtocol {
  
  public typealias Producer = @Sendable (Continuation) async throws -> Void
  
  public struct Continuation {
    
    private let context: RelayContext<Result<Element?, Error>>
    
    fileprivate init(_ context: RelayContext<Result<Element?, Error>>) {
      self.context = context
    }
    
    public func callAsFunction(_ element: Element) async {
      await context.yield(.success(element))
    }
  }
  
  private enum TaskState {
    case pending
    case running(Task<Void, Never>)
    case terminal
  }
  
  private let taskState = ManagedCriticalState<TaskState>(.pending)
  private let context: RelayContext<Result<Element?, Error>>
  private let producer: Producer
  private let deallocToken: DeallocToken
  
  public init(_ producer: @escaping Producer) {
    self.context = .init()
    self.producer = producer
    self.deallocToken = .init  { [taskState, context] in
      taskState.withCriticalRegion { taskState in
        if case .running(let task) = taskState { task.cancel() }
        taskState = .terminal
      }
      context.cancel()
    }
  }
  
  public func next() async throws -> Element? {
    guard Task.isCancelled == false else { return nil }
    taskState.withCriticalRegion { [producer, context] taskState in
      guard case .pending = taskState else { return }
      let task = Task {
        do {
          try await producer(Continuation(context))
        }
        catch {
          await context.yield(.failure(error))
        }
        context.cancel()
      }
      taskState = .running(task)
    }
    let result = await context.next() ?? .success(nil)
    return try result.get()
  }
}

// MARK: - Relay Context

fileprivate struct RelayContext<Element: Sendable> : Sendable {
  
  private typealias NextContinuation = @Sendable (Element?) -> Void
  private typealias NextBox = SealableBox<NextContinuation>
  
  private struct State: Sendable {
    
    var active = true
    var pendingNexts = Deque<NextBox>()
    var pendingYield: UnsafeContinuation<Bool, Never>?
    var pendingElement: Element?
    
    mutating func next(_ nextBox: NextBox) -> (() -> Void)? {
      guard active else {
        if let continuation = nextBox.remove(sealingForInsertions: true) {
          return { continuation(nil) }
        }
        else {
          return nil
        }
      }
      // If there's already queued nexts, we should simply add to the back
      // of the queue. It will be resumed in a later yield cycle.
      guard pendingNexts.isEmpty else {
        pendingNexts.append(nextBox)
        return nil
      }
      return attemptNext(nextBox)
    }
    
    private mutating func attemptNext(_ nextBox: NextBox) -> (() -> Void)? {
      if let element = pendingElement {
        guard let continuation = nextBox.remove(sealingForInsertions: true) else {
          return nil
        }
        // We have an element already, so return it. No need to kick-off
        // another cycle. The element was either produced as part of the first
        // iteration, or from a previous next that was cancelled mid yield
        // cycle
        self.pendingElement = nil
        return { continuation(element) }
      }
      else if let yield = pendingYield {
        // there's no element, so we need to kick off a yield cycle to get one
        pendingNexts.append(nextBox)
        pendingYield = nil
        return { yield.resume(returning: true) }
      }
      else {
        // There's no element, OR pending yield. Probably arrived before the
        // first iteration's `yield` call. Enqueue the pending `next`
        // continuation and wait for `yield` to be called.
        pendingNexts.append(nextBox)
        return nil
      }
    }
    
    mutating func yield(
      _ continuation: UnsafeContinuation<Bool, Never>, element: Element
    ) -> (() -> Void)? {
      precondition(pendingYield == nil, "attempt to await yield() on more then one task")
      precondition(pendingElement == nil, "attempt to await yield() on more then one task")
      // We're finishing a yield cycle so there should be a waiting next –
      // assuming it wasn't cancelled
      if let pendingNext = pendingNexts.first {
        pendingNexts.removeFirst()
        guard let nextContinuation = pendingNext.remove(sealingForInsertions: true) else {
          // The waiting next was cancelled before being used. Try again. There
          // may be another awaiting Task queued.
          return yield(continuation, element: element)
        }
        if pendingNexts.isEmpty {
          // There's no more tasks awaiting next after this one, hold on to the
          // yield continuation until one arrives
          self.pendingYield = continuation
          return { nextContinuation(element) }
        }
        else {
          // There's more tasks awaiting next after this one, so kick-off the
          // next yield cycle straight away.
          return {
            nextContinuation(element)
            continuation.resume(returning: true)
          }
        }
      }
      // There's no tasks awaiting next. Maybe they were cancelled. Or,
      // perhaps this is the first iteration.
      else {
        self.pendingElement = element
        self.pendingYield = continuation
        return nil
      }
    }
    
    mutating func cancel() -> (() -> Void)? {
      self.active = false
      let pendingYield = self.pendingYield
      let pendingNexts = self.pendingNexts.compactMap { box in
        box.remove(sealingForInsertions: true)
      }
      self.pendingYield = nil
      self.pendingElement = nil
      self.pendingNexts.removeAll()
      return {
        for continuation in pendingNexts { continuation(nil) }
        pendingYield?.resume(returning: false)
      }
    }
  }
  
  private let state = ManagedCriticalState(State())
  
  func next() async -> Element? {
    // triggers yield cycle, suspending until yield is called
    let nextBox = NextBox()
    return await withTaskCancellationHandler {
      return await withUnsafeContinuation { continuation in
        let contents = { @Sendable element in continuation.resume(returning: element) }
        guard nextBox.insert(contents) else {
          continuation.resume(returning: nil)
          return
        }
        let resume = state.withCriticalRegion { state in state.next(nextBox) }
        resume?()
      }
    } onCancel: {
      guard let continuation = nextBox.remove(sealingForInsertions: true) else { return }
      continuation(nil)
    }
  }
  
  @discardableResult
  func yield(_ element: Element) async -> Bool {
    // suspends yield cycle, suspending until next is called
    await withUnsafeContinuation { continuation in
      let resume = state.withCriticalRegion { state in
        state.yield(continuation, element: element)
      }
      resume?()
    }
  }
  
  func cancel() {
    let resume = state.withCriticalRegion { state in state.cancel() }
    resume?()
  }
}

// MARK: - Utilities

fileprivate struct SealableBox<Element: Sendable>: Sendable {
  
  enum State {
    case empty
    case full(Element)
    case sealed
  }
  
  private let box = ManagedCriticalState(State.empty)
  
  func insert(_ element: Element) -> Bool {
    box.withCriticalRegion { state in
      guard case .empty = state else {
        return false
      }
      state = .full(element)
      return true
    }
  }
  
  func remove(sealingForInsertions sealed: Bool = false) -> Element? {
    box.withCriticalRegion { state in
      switch state {
      case .empty:
        state = sealed ? .sealed : .empty
        return nil
      case .full(let element):
        state = sealed ? .sealed : .empty
        return element
      case .sealed:
        return nil
      }
    }
  }
}

/// A utility to perform deallocation tasks on value types
fileprivate final class DeallocToken: Sendable {
  let action: @Sendable () -> Void
  init(_ dealloc: @escaping @Sendable () -> Void) {
    self.action = dealloc
  }
  deinit { action() }
}

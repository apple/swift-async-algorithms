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

extension AsyncSequence {
  
  /// Creates a ``StartableSequence`` that suspends the output of its Iterator until `enter()` is called `count` times.
  public func delayed(_ count: Int) -> StartableSequence<Self> {
    StartableSequence(self, count: count)
  }
}

/// An `AsyncSequence` that delays publishing elements until an entry threshold has been reached.
/// Once the entry threshold has been met the sequence proceeds as normal.
public struct StartableSequence<Base: AsyncSequence> {
  
  private let base: Base
  private let semaphore: BasicSemaphore
  
  /// Decrements the entry counter and, upon reaching zero, resumes the iterator
  public func enter() {
    semaphore.signal()
  }
  
  /// Creates new ``StartableSequence`` with an initial entry count
  public init(_ base: Base, count: Int) {
    self.base = base
    self.semaphore = .init(count: 1 - count)
  }
}

extension StartableSequence: AsyncSequence {
  
  public typealias Element = Base.Element
  
  public struct Iterator: AsyncIteratorProtocol {
    
    private var iterator: Base.AsyncIterator
    private var terminal = false
    private let semaphore: BasicSemaphore
    private let id = Int.random(in: 0...100_000)
    
    init(iterator: Base.AsyncIterator, semaphore: BasicSemaphore) {
      self.iterator = iterator
      self.semaphore = semaphore
    }
    
    public mutating func next() async rethrows -> Element? {
      await semaphore.wait()
      semaphore.signal()
      if terminal { return nil }
      do {
        guard let value = try await iterator.next() else {
          self.terminal = true
          return nil
        }
        return value
      }
      catch {
        self.terminal = true
        throw error
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(iterator: base.makeAsyncIterator(), semaphore: semaphore)
  }
}

extension StartableSequence: Sendable where Base: Sendable { }
extension StartableSequence.Iterator: Sendable where Base.AsyncIterator: Sendable { }

struct BasicSemaphore {
  
  struct State {
    var count: Int
    var continuations: [UnsafeContinuation<Void, Never>]
  }
  
  private let state: ManagedCriticalState<State>
  
  /// Creates new counting semaphore with an initial value.
  init(count: Int) {
    self.state = ManagedCriticalState(.init(count: count, continuations: []))
  }
  
  /// Waits for, or decrements, a semaphore.
  func wait() async {
    await withUnsafeContinuation { continuation in
      let shouldImmediatelyResume = state.withCriticalRegion { state in
        state.count -= 1
        if state.count < 0 {
          state.continuations.append(continuation)
          return false
        }
        else {
          return true
        }
      }
      if shouldImmediatelyResume { continuation.resume() }
    }
  }
  
  /// Signals (increments) a semaphore.
  func signal() {
    let continuations = state.withCriticalRegion { state -> [UnsafeContinuation<Void, Never>] in
      state.count += 1
      if state.count >= 0 {
        defer { state.continuations = [] }
        return state.continuations
      }
      else {
        return []
      }
    }
    for continuation in continuations { continuation.resume() }
  }
}

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

/// An `AsyncSequence` that delays publishing elements until an entry threshold has been reached.
/// Once the entry threshold has been met the sequence proceeds as normal.
public struct GatedStartSequence<Element: Sendable>: Sendable {
  
  private let elements: [Element]
  private let semaphore: BasicSemaphore
  
  /// Decrements the entry counter and, upon reaching zero, resumes the iterator
  public func enter() {
    semaphore.signal()
  }
  
  /// Creates new ``StartableSequence`` with an initial entry count
  public init<T: Sequence>(_ elements: T, count: Int) where T.Element == Element {
    self.elements = Array(elements)
    self.semaphore = .init(count: 1 - count)
  }
}

extension GatedStartSequence: AsyncSequence {
  
  public struct Iterator: AsyncIteratorProtocol {
    
    private var elements: [Element]
    private let semaphore: BasicSemaphore
    
    init(elements: [Element], semaphore: BasicSemaphore) {
      self.elements = elements
      self.semaphore = semaphore
    }
    
    public mutating func next() async -> Element? {
      await semaphore.wait()
      semaphore.signal()
      guard let element = elements.first else { return nil }
      elements.removeFirst()
      return element
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(elements: elements, semaphore: semaphore)
  }
}

struct BasicSemaphore {
  
  private struct State {
    
    var count: Int
    var continuations = [UnsafeContinuation<Void, Never>]()
    
    mutating func wait(continuation: UnsafeContinuation<Void, Never>) -> (() -> Void)? {
      count -= 1
      if count < 0 {
        continuations.append(continuation)
        return nil
      }
      else {
        return { continuation.resume() }
      }
    }
    
    mutating func signal() -> (() -> Void)? {
      count += 1
      if count >= 0 {
        let continuations = self.continuations
        self.continuations.removeAll()
        return  {
          for continuation in continuations { continuation.resume() }
        }
      }
      else {
        return nil
      }
    }
  }
  
  private let state: ManagedCriticalState<State>
  
  /// Creates new counting semaphore with an initial value.
  init(count: Int) {
    self.state = ManagedCriticalState(State(count: count))
  }
  
  /// Waits for, or decrements, a semaphore.
  func wait() async {
    await withUnsafeContinuation { continuation in
      let resume = state.withCriticalRegion { $0.wait(continuation: continuation) }
      resume?()
    }
  }
  
  /// Signals (increments) a semaphore.
  func signal() {
    let resume = state.withCriticalRegion { $0.signal() }
    resume?()
  }
}

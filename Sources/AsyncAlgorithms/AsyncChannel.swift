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

/// A channel for sending elements from one task to another with back pressure.
///
/// The `AsyncChannel` class is intended to be used as a communication type between tasks,
/// particularly when one task produces values and another task consumes those values. The back
///  pressure applied by `send(_:)` and `finish()` via the suspension/resume ensure that
///  the production of values does not exceed the consumption of values from iteration. Each of these
///  methods suspends after enqueuing the event and is resumed when the next call to `next()`
///  on the `Iterator` is made.
public final class AsyncChannel<Element: Sendable>: AsyncSequence, Sendable {
  /// The iterator for a `AsyncChannel` instance.
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let channel: AsyncChannel<Element>
    var active: Bool = true
    
    init(_ channel: AsyncChannel<Element>) {
      self.channel = channel
    }
    
    /// Await the next sent element or finish.
    public mutating func next() async -> Element? {
      guard active else {
        return nil
      }
      let generation = channel.establish()
      let value: Element? = await withTaskCancellationHandler { [channel] in
        channel.cancel(generation)
      } operation: {
        await channel.next(generation)
      }
      
      if let value = value {
        return value
      } else {
        active = false
        return nil
      }
    }
  }
  
  struct Awaiting: Hashable {
    var generation: Int
    var continuation: UnsafeContinuation<Element?, Never>?
    let cancelled: Bool
    
    init(generation: Int, continuation: UnsafeContinuation<Element?, Never>) {
      self.generation = generation
      self.continuation = continuation
      cancelled = false
    }
    
    init(placeholder generation: Int) {
      self.generation = generation
      self.continuation = nil
      cancelled = false
    }
    
    init(cancelled generation: Int) {
      self.generation = generation
      self.continuation = nil
      cancelled = true
    }
    
    func hash(into hasher: inout Hasher) {
      hasher.combine(generation)
    }
    
    static func == (_ lhs: Awaiting, _ rhs: Awaiting) -> Bool {
      return lhs.generation == rhs.generation
    }
  }
  
  enum Emission {
    case idle
    case pending([UnsafeContinuation<UnsafeContinuation<Element?, Never>?, Never>])
    case awaiting(Set<Awaiting>)
    
    mutating func cancel(_ generation: Int) -> UnsafeContinuation<Element?, Never>? {
      switch self {
      case .awaiting(var awaiting):
        let continuation = awaiting.remove(Awaiting(placeholder: generation))?.continuation
        if awaiting.isEmpty {
          self = .idle
        } else {
          self = .awaiting(awaiting)
        }
        return continuation
      case .idle:
        self = .awaiting([Awaiting(cancelled: generation)])
        return nil
      default:
        return nil
      }
    }
  }
  
  struct State {
    var emission: Emission = .idle
    var generation = 0
    var terminal = false
  }
  
  let state = ManagedCriticalState(State())
  
  /// Create a new `AsyncChannel` given an element type.
  public init(element elementType: Element.Type = Element.self) { }
  
  func establish() -> Int {
    state.withCriticalRegion { state in
      defer { state.generation &+= 1 }
      return state.generation
    }
  }
  
  func cancel(_ generation: Int) {
    state.withCriticalRegion { state in
      state.emission.cancel(generation)
    }?.resume(returning: nil)
  }
  
  func next(_ generation: Int) async -> Element? {
    return await withUnsafeContinuation { continuation in
      var cancelled = false
      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Never>?, Never>? in
        switch state.emission {
        case .idle:
          state.emission = .awaiting([Awaiting(generation: generation, continuation: continuation)])
          return nil
        case .pending(var sends):
          let send = sends.removeFirst()
          if sends.count == 0 {
            state.emission = .idle
          } else {
            state.emission = .pending(sends)
          }
          return UnsafeResumption(continuation: send, success: continuation)
        case .awaiting(var nexts):
          if nexts.update(with: Awaiting(generation: generation, continuation: continuation)) != nil {
            nexts.remove(Awaiting(placeholder: generation))
            cancelled = true
          }
          if nexts.isEmpty {
            state.emission = .idle
          } else {
            state.emission = .awaiting(nexts)
          }
          return nil
        }
      }?.resume()
      if cancelled {
        continuation.resume(returning: nil)
      }
    }
  }
  
  func cancelSend() {
    let (sends, nexts) = state.withCriticalRegion { state -> ([UnsafeContinuation<UnsafeContinuation<Element?, Never>?, Never>], Set<Awaiting>) in
      if state.terminal {
        return ([], [])
      }
      state.terminal = true
      switch state.emission {
      case .idle:
        return ([], [])
      case .pending(let nexts):
        state.emission = .idle
        return (nexts, [])
      case .awaiting(let nexts):
        state.emission = .idle
        return ([], nexts)
      }
    }
    for send in sends {
      send.resume(returning: nil)
    }
    for next in nexts {
      next.continuation?.resume(returning: nil)
    }
  }
  
  func _send(_ result: Result<Element?, Never>) async {
    await withTaskCancellationHandler {
      cancelSend()
    } operation: {
      let continuation: UnsafeContinuation<Element?, Never>? = await withUnsafeContinuation { continuation in
        state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Never>?, Never>? in
          if state.terminal {
            return UnsafeResumption(continuation: continuation, success: nil)
          }
          switch result {
          case .success(let value):
            if value == nil {
              state.terminal = true
            }
          case .failure:
            state.terminal = true
          }
          switch state.emission {
          case .idle:
            state.emission = .pending([continuation])
            return nil
          case .pending(var sends):
            sends.append(continuation)
            state.emission = .pending(sends)
            return nil
          case .awaiting(var nexts):
            let next = nexts.removeFirst().continuation
            if nexts.count == 0 {
              state.emission = .idle
            } else {
              state.emission = .awaiting(nexts)
            }
            return UnsafeResumption(continuation: continuation, success: next)
          }
        }?.resume()
      }
      continuation?.resume(with: result)
    }
  }
  
  /// Send an element to an awaiting iteration. This function will resume when the next call to `next()` is made.
  /// If the channel is already finished then this returns immediately
  public func send(_ element: Element) async {
      await _send(.success(element))
  }
  
  /// Send a finish to an awaiting iteration. This function will resume when the next call to `next()` is made.
  /// If the channel is already finished then this returns immediately
  public func finish() async {
      await _send(.success(nil))
  }
  
  /// Create an `Iterator` for iteration of an `AsyncChannel`
  public func makeAsyncIterator() -> Iterator {
    return Iterator(self)
  }
}

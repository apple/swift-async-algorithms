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

/// An error-throwing channel for sending elements from on task to another with back pressure.
///
/// The `AsyncThrowingChannel` class is intended to be used as a communication types between tasks,
/// particularly when one task produces values and another task consumes those values. The back
/// pressure applied by `send(_:)` via suspension/resume ensures that the production of values does
/// not exceed the consumption of values from iteration. This method suspends after enqueuing the event
/// and is resumed when the next call to `next()` on the `Iterator` is made, or when `finish()`/`fail(_:)` is called
/// from another Task. As `finish()` and `fail(_:)` induce a terminal state, there is no need for a back pressure management.
/// Those functions do not suspend and will finish all the pending iterations.
public final class AsyncThrowingChannel<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  /// The iterator for an `AsyncThrowingChannel` instance.
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let channel: AsyncThrowingChannel<Element, Failure>
    var active: Bool = true
    
    init(_ channel: AsyncThrowingChannel<Element, Failure>) {
      self.channel = channel
    }
    
    public mutating func next() async throws -> Element? {
      guard active else {
        return nil
      }
      let generation = channel.establish()
      do {
        let value: Element? = try await withTaskCancellationHandler { [channel] in
          channel.cancel(generation)
        } operation: {
          try await channel.next(generation)
        }
        
        if let value = value {
          return value
        } else {
          active = false
          return nil
        }
      } catch {
        active = false
        throw error
      }
    }
  }
  
  struct Awaiting: Hashable {
    var generation: Int
    var continuation: UnsafeContinuation<Element?, Error>?
    let cancelled: Bool
    
    init(generation: Int, continuation: UnsafeContinuation<Element?, Error>) {
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

  enum Termination {
    case finished
    case failed(Error)
  }
  
  enum Emission {
    case idle
    case pending([UnsafeContinuation<UnsafeContinuation<Element?, Error>?, Never>])
    case awaiting(Set<Awaiting>)
    case terminated(Termination)

    var isTerminated: Bool {
      guard case .terminated = self else { return false }
      return true
    }

    mutating func cancel(_ generation: Int) -> UnsafeContinuation<Element?, Error>? {
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
  }

  let state = ManagedCriticalState(State())
  
  public init(_ elementType: Element.Type = Element.self) { }
  
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
  
  func next(_ generation: Int) async throws -> Element? {
    return try await withUnsafeThrowingContinuation { continuation in
      var cancelled = false
      var potentialTermination: Termination?

      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Error>?, Never>? in
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
        case .terminated(let termination):
          potentialTermination = termination
          state.emission = .terminated(.finished)
          return nil
        }
      }?.resume()

      if cancelled {
        continuation.resume(returning: nil)
        return
      }

      switch potentialTermination {
      case .none:
        return
      case .failed(let error):
        continuation.resume(throwing: error)
        return
      case .finished:
        continuation.resume(returning: nil)
        return
      }
    }
  }

  func terminateAll(error: Failure? = nil) {
    let (sends, nexts) = state.withCriticalRegion { state -> ([UnsafeContinuation<UnsafeContinuation<Element?, Error>?, Never>], Set<Awaiting>) in

      let nextState: Emission
      if let error = error {
        nextState = .terminated(.failed(error))
      } else {
        nextState = .terminated(.finished)
      }

      switch state.emission {
      case .idle:
        state.emission = nextState
        return ([], [])
      case .pending(let nexts):
        state.emission = nextState
        return (nexts, [])
      case .awaiting(let nexts):
        state.emission = nextState
        return ([], nexts)
      case .terminated:
        return ([], [])
      }
    }

    for send in sends {
      send.resume(returning: nil)
    }

    if let error = error {
      for next in nexts {
        next.continuation?.resume(throwing: error)
      }
    } else {
      for next in nexts {
        next.continuation?.resume(returning: nil)
      }
    }

  }
  
  func _send(_ element: Element) async {
    await withTaskCancellationHandler {
      terminateAll()
    } operation: {
      let continuation: UnsafeContinuation<Element?, Error>? = await withUnsafeContinuation { continuation in
        state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Error>?, Never>? in
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
          case .terminated:
            return UnsafeResumption(continuation: continuation, success: nil)
          }
        }?.resume()
      }
      continuation?.resume(returning: element)
    }
  }
  
  /// Send an element to an awaiting iteration. This function will resume when the next call to `next()` is made
  /// or when a call to `finish()`/`fail(_:)` is made from another Task.
  /// If the channel is already finished then this returns immediately
  public func send(_ element: Element) async {
      await _send(element)
  }
  
  /// Send an error to all awaiting iterations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func fail(_ error: Error) where Failure == Error {
    terminateAll(error: error)
  }
  
  /// Send a finish to all awaiting iterations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func finish() {
    terminateAll()
  }
  
  public func makeAsyncIterator() -> Iterator {
    return Iterator(self)
  }
}

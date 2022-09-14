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

import OrderedCollections

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
      let nextTokenStatus = ManagedCriticalState<ChannelTokenStatus>(.new)

      do {
        let value = try await withTaskCancellationHandler { [channel] in
          channel.cancelNext(nextTokenStatus, generation)
        } operation: {
          try await channel.next(nextTokenStatus, generation)
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

  typealias Pending = ChannelToken<UnsafeContinuation<UnsafeContinuation<Element?, Error>?, Never>>
  typealias Awaiting = ChannelToken<UnsafeContinuation<Element?, Error>>

  struct ChannelToken<Continuation>: Hashable {
    var generation: Int
    var continuation: Continuation?

    init(generation: Int, continuation: Continuation) {
      self.generation = generation
      self.continuation = continuation
    }

    init(placeholder generation: Int) {
      self.generation = generation
      self.continuation = nil
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(generation)
    }

    static func == (_ lhs: ChannelToken, _ rhs: ChannelToken) -> Bool {
      return lhs.generation == rhs.generation
    }
  }


  enum ChannelTokenStatus: Equatable {
    case new
    case cancelled
  }

  enum Termination {
    case finished
    case failed(Error)
  }
  
  enum Emission {
    case idle
    case pending(OrderedSet<Pending>)
    case awaiting(OrderedSet<Awaiting>)
    case terminated(Termination)
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

  func cancelNext(_ nextTokenStatus: ManagedCriticalState<ChannelTokenStatus>, _ generation: Int) {
    state.withCriticalRegion { state -> UnsafeContinuation<Element?, Error>? in
      let continuation: UnsafeContinuation<Element?, Error>?

      switch state.emission {
      case .awaiting(var nexts):
        continuation = nexts.remove(Awaiting(placeholder: generation))?.continuation
        if nexts.isEmpty {
          state.emission = .idle
        } else {
          state.emission = .awaiting(nexts)
        }
      default:
        continuation = nil
      }

      nextTokenStatus.withCriticalRegion { status in
        if status == .new {
          status = .cancelled
        }
      }

      return continuation
    }?.resume(returning: nil)
  }
  
  func next(_ nextTokenStatus: ManagedCriticalState<ChannelTokenStatus>, _ generation: Int) async throws -> Element? {
    return try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Element?, Error>) in
      var cancelled = false
      var potentialTermination: Termination?

      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Error>?, Never>? in

        if nextTokenStatus.withCriticalRegion({ $0 }) == .cancelled {
          cancelled = true
          return nil
        }

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
          return UnsafeResumption(continuation: send.continuation, success: continuation)
        case .awaiting(var nexts):
          nexts.updateOrAppend(Awaiting(generation: generation, continuation: continuation))
          state.emission = .awaiting(nexts)
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

  func cancelSend(_ sendTokenStatus: ManagedCriticalState<ChannelTokenStatus>, _ generation: Int) {
    state.withCriticalRegion { state -> UnsafeContinuation<UnsafeContinuation<Element?, Error>?, Never>? in
      let continuation: UnsafeContinuation<UnsafeContinuation<Element?, Error>?, Never>?

      switch state.emission {
      case .pending(var sends):
        let send = sends.remove(Pending(placeholder: generation))
        if sends.isEmpty {
          state.emission = .idle
        } else {
          state.emission = .pending(sends)
        }
        continuation = send?.continuation
      default:
        continuation = nil
      }

      sendTokenStatus.withCriticalRegion { status in
        if status == .new {
          status = .cancelled
        }
      }

      return continuation
    }?.resume(returning: nil)
  }
  
  func send(_ sendTokenStatus: ManagedCriticalState<ChannelTokenStatus>, _ generation: Int, _ element: Element) async {
    let continuation: UnsafeContinuation<Element?, Error>? = await withUnsafeContinuation { continuation in
      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Error>?, Never>? in

        if sendTokenStatus.withCriticalRegion({ $0 }) == .cancelled {
          return UnsafeResumption(continuation: continuation, success: nil)
        }

        switch state.emission {
        case .idle:
          state.emission = .pending([Pending(generation: generation, continuation: continuation)])
          return nil
        case .pending(var sends):
          sends.updateOrAppend(Pending(generation: generation, continuation: continuation))
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

  func terminateAll(error: Failure? = nil) {
    let (sends, nexts) = state.withCriticalRegion { state -> (OrderedSet<Pending>, OrderedSet<Awaiting>) in

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
      send.continuation?.resume(returning: nil)
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
  
  /// Send an element to an awaiting iteration. This function will resume when the next call to `next()` is made
  /// or when a call to `finish()`/`fail(_:)` is made from another Task.
  /// If the channel is already finished then this returns immediately
  /// If the task is cancelled, this function will resume. Other sending operations from other tasks will remain active.
  public func send(_ element: Element) async {
    let generation = establish()
    let sendTokenStatus = ManagedCriticalState<ChannelTokenStatus>(.new)

    await withTaskCancellationHandler { [weak self] in
      self?.cancelSend(sendTokenStatus, generation)
    } operation: {
      await send(sendTokenStatus, generation, element)
    }
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

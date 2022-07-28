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

/// A channel for sending elements from one task to another with back pressure.
///
/// The `AsyncChannel` class is intended to be used as a communication type between tasks,
/// particularly when one task produces values and another task consumes those values. The back
/// pressure applied by `send(_:)` via the suspension/resume ensures that
/// the production of values does not exceed the consumption of values from iteration. This method
/// suspends after enqueuing the event and is resumed when the next call to `next()`
/// on the `Iterator` is made, or when `finish()` is called from another Task.
/// As `finish()` induces a terminal state, there is no need for a back pressure management.
/// This function does not suspend and will finish all the pending iterations.
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
      let nextTokenStatus = ManagedCriticalState<ChannelTokenStatus>(.new)

      let value = await withTaskCancellationHandler { [channel] in
        channel.cancelNext(nextTokenStatus, generation)
      } operation: {
        await channel.next(nextTokenStatus, generation)
      }

      if let value {
        return value
      } else {
        active = false
        return nil
      }
    }
  }
  
  typealias Pending = ChannelToken<UnsafeContinuation<UnsafeContinuation<Element?, Never>?, Never>>
  typealias Awaiting = ChannelToken<UnsafeContinuation<Element?, Never>>

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
  
  enum Emission {
    case idle
    case pending(OrderedSet<Pending>)
    case awaiting(OrderedSet<Awaiting>)
    case finished
  }
  
  struct State {
    var emission: Emission = .idle
    var generation = 0
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

  func cancelNext(_ nextTokenStatus: ManagedCriticalState<ChannelTokenStatus>, _ generation: Int) {
    state.withCriticalRegion { state -> UnsafeContinuation<Element?, Never>? in
      let continuation: UnsafeContinuation<Element?, Never>?

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

  func next(_ nextTokenStatus: ManagedCriticalState<ChannelTokenStatus>, _ generation: Int) async -> Element? {
    return await withUnsafeContinuation { (continuation: UnsafeContinuation<Element?, Never>) in
      var cancelled = false
      var terminal = false
      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Never>?, Never>? in

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
        case .finished:
          terminal = true
          return nil
        }
      }?.resume()

      if cancelled || terminal {
        continuation.resume(returning: nil)
      }
    }
  }

  func cancelSend(_ sendTokenStatus: ManagedCriticalState<ChannelTokenStatus>, _ generation: Int) {
    state.withCriticalRegion { state -> UnsafeContinuation<UnsafeContinuation<Element?, Never>?, Never>? in
      let continuation: UnsafeContinuation<UnsafeContinuation<Element?, Never>?, Never>?

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
    let continuation = await withUnsafeContinuation { continuation in
      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Never>?, Never>? in

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
        case .finished:
          return UnsafeResumption(continuation: continuation, success: nil)
        }
      }?.resume()
    }
    continuation?.resume(returning: element)
  }

  /// Send an element to an awaiting iteration. This function will resume when the next call to `next()` is made
  /// or when a call to `finish()` is made from another Task.
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
  
  /// Send a finish to all awaiting iterations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func finish() {
    let (sends, nexts) = state.withCriticalRegion { state -> (OrderedSet<Pending>, OrderedSet<Awaiting>) in
      let result: (OrderedSet<Pending>, OrderedSet<Awaiting>)

      switch state.emission {
      case .idle:
        result = ([], [])
      case .pending(let nexts):
        result = (nexts, [])
      case .awaiting(let nexts):
        result = ([], nexts)
      case .finished:
        result = ([], [])
      }

      state.emission = .finished

      return result
    }
    for send in sends {
      send.continuation?.resume(returning: nil)
    }
    for next in nexts {
      next.continuation?.resume(returning: nil)
    }
  }
  
  /// Create an `Iterator` for iteration of an `AsyncChannel`
  public func makeAsyncIterator() -> Iterator {
    return Iterator(self)
  }
}

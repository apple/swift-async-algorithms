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

///
public final class AsyncSubject<Element: Sendable>: AsyncSequence, Sendable {
  /// The iterator for an `AsyncSubject` instance.
  public struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
    private let subject: AsyncSubject<Element>
    private var active: Bool = true

    fileprivate init(_ subject: AsyncSubject<Element>) {
      self.subject = subject
    }

    /// Await the next sent element or finish.
    public mutating func next() async -> Element? {
      guard active else {
        return nil
      }

      guard let value = await subject.next() else {
        active = false
        return nil
      }
      return value
    }
  }

  private let state: ManagedCriticalState<State>

  private func next() async -> Element? {
    await withTaskCancellationHandler {
      await withUnsafeContinuation { continuation in
        next(continuation)
      }
    } onCancel: { [cancel] in
      cancel()
    }
  }

  /// Create a new `AsyncSubject` given an element type.
  public init(element elementType: Element.Type = Element.self, bufferingPolicy limit: BufferingPolicy = .unbounded) {
    state = .init(.init(limit: limit))
  }

  deinit {
    guard let handler = state.withCriticalRegion({ state in
      // swap out the handler before we invoke it to prevent double cancel
      let handler = state.onTermination
      state.onTermination = nil
      return handler
    }) else { return }
    handler(.cancelled)
  }

  /// Resume the task awaiting the next iteration point by having it return
  /// normally from its suspension point with a given element.
  ///
  /// - Parameter value: The value to send from the continuation.
  /// - Returns: A `SendResult` that indicates the success or failure of the
  ///   send operation.
  ///
  /// If nothing is awaiting the next value, this method attempts to buffer the
  /// result's element.
  ///
  /// This can be called more than once and returns to the caller immediately
  /// without blocking for any awaiting consumption from the iteration.
  @discardableResult
  public func send(_ element: Element) -> SendResult {
    let (result, continuation, toSend) = state.withCriticalRegion { state in
      var result: SendResult
      var continuation: UnsafeContinuation<Element?, Never>?
      var toSend: Element?

      let limit = state.limit
      let count = state.pending.count

      guard !state.continuations.isEmpty else {
        if !state.terminal {
          switch limit {
          case .unbounded:
            result = .enqueued(remaining: .max)
            state.pending.append(element)
          case .bufferingOldest(let limit):
            if count < limit {
              result = .enqueued(remaining: limit - (count + 1))
              state.pending.append(element)
            } else {
              result = .dropped(element)
            }
          case .bufferingNewest(let limit):
            if count < limit {
              state.pending.append(element)
              result = .enqueued(remaining: limit - (count + 1))
            } else if count > 0 {
              result = .dropped(state.pending.removeFirst())
              state.pending.append(element)
            } else {
              result = .dropped(element)
            }
          }
        } else {
          result = .terminated
        }
        return (result, continuation, toSend)
      }
      continuation = state.continuations.removeFirst()
      if count > 0 {
        if !state.terminal {
          switch limit {
          case .unbounded:
            state.pending.append(element)
            result = .enqueued(remaining: .max)
          case .bufferingOldest(let limit):
            if count < limit {
              state.pending.append(element)
              result = .enqueued(remaining: limit - (count + 1))
            } else {
              result = .dropped(element)
            }
          case .bufferingNewest(let limit):
            if count < limit {
              state.pending.append(element)
              result = .enqueued(remaining: limit - (count + 1))
            } else if count > 0 {
              result = .dropped(state.pending.removeFirst())
              state.pending.append(element)
            } else {
              result = .dropped(element)
            }
          }
        } else {
          result = .terminated
        }
        toSend = state.pending.removeFirst()
      } else if state.terminal {
        result = .terminated
      } else {
        switch limit {
        case .unbounded:
          result = .enqueued(remaining: .max)
        case .bufferingNewest(let limit):
          result = .enqueued(remaining: limit)
        case .bufferingOldest(let limit):
          result = .enqueued(remaining: limit)
        }
        toSend = element
      }
      return (result, continuation, toSend)
    }
    continuation?.resume(returning: toSend)
    return result
  }

  /// Send a finish to all awaiting iterations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func finish() {
    let (handler, continuation, toSend) = state.withCriticalRegion { state -> (TerminationHandler?, UnsafeContinuation<Element?, Never>?, Element?) in
      let handler = state.onTermination
      state.onTermination = nil
      state.terminal = true

      if let continuation = state.continuations.first {
        if state.pending.count > 0 {
          state.continuations.removeFirst()
          let toSend = state.pending.removeFirst()
          return (handler, continuation, toSend)
        } else if state.terminal {
          state.continuations.removeFirst()
          return (handler, continuation, nil)
        } else {
          return (handler, nil, nil)
        }
      } else {
        return (handler, nil, nil)
      }
    }
    handler?(.finished)
    continuation?.resume(returning: toSend)
  }

  /// A callback to invoke when canceling iteration of an asynchronous
  /// stream.
  ///
  /// If an `onTermination` callback is set, using task cancellation to
  /// terminate iteration of an `AsyncStream` results in a call to this
  /// callback.
  ///
  /// Canceling an active iteration invokes the `onTermination` callback
  /// first, then resumes by yielding `nil`. This means that you can perform
  /// needed cleanup in the cancellation handler. After reaching a terminal
  /// state as a result of cancellation, the `AsyncStream` sets the callback
  /// to `nil`.
  public var onTermination: (@Sendable (Termination) -> Void)? {
    get {
      state.withCriticalRegion { state in
        state.onTermination
      }
    }
    set {
      state.withCriticalRegion { state in
        state.onTermination = newValue
      }
    }
  }

  /// Create an `Iterator` for iteration of an `AsyncSubject`
  public func makeAsyncIterator() -> Iterator {
    Iterator(self)
  }
}

extension AsyncSubject {
  /// A type that indicates how the subject terminated.
  ///
  /// The `onTermination` closure receives an instance of this type.
  public enum Termination {
    /// The subject finished as a result of calling the `finish` method.
    case finished

    /// The subject finished as a result of cancellation.
    case cancelled
  }
}

extension AsyncSubject {
  /// A type that indicates the result of sending a value to a client
  public enum SendResult {
    /// The subject successfully enqueued the element.
    ///
    /// This value represents the successful enqueueing of an element, whether
    /// the subject buffers the element or delivers it immediately to a pending
    /// call to `next()`. The associated value `remaining` is a hint that
    /// indicates the number of remaining slots in the buffer at the time of
    /// the `send` call.
    ///
    /// - Note: From a thread safety point of view, `remaining` is a lower bound
    /// on the number of remaining slots. This is because a subsequent call
    /// that uses the `remaining` value could race on the consumption of
    /// values from the subject.
    case enqueued(remaining: Int)
    
    /// The subject didn't enqueue the element because the buffer was full.
    ///
    /// The associated element for this case is the element dropped by the subject.
    case dropped(Element)
    
    /// The subject didn't enqueue the element because the subject was in a
    /// terminal state.
    ///
    /// This indicates the subject terminated prior to calling `send`, either
    /// because the subject finished normally or through cancellation.
    case terminated
  }
}

extension AsyncSubject {
  /// A strategy that handles exhaustion of a buffer’s capacity.
  public enum BufferingPolicy: Sendable {
    /// Continue to add to the buffer, without imposing a limit on the number
    /// of buffered elements.
    case unbounded

    /// When the buffer is full, discard the newly received element.
    ///
    /// This strategy enforces keeping at most the specified number of oldest
    /// values.
    case bufferingOldest(Int)

    /// When the buffer is full, discard the oldest element in the buffer.
    ///
    /// This strategy enforces keeping at most the specified number of newest
    /// values.
    case bufferingNewest(Int)
  }
}

extension AsyncSubject {
  fileprivate typealias TerminationHandler = @Sendable (Termination) -> Void

  
  fileprivate struct State: Sendable {
    var onTermination: TerminationHandler?
    var continuations = [UnsafeContinuation<Element?, Never>]()
    var pending = Deque<Element>()
    let limit: BufferingPolicy
    var terminal: Bool = false

    init(limit: BufferingPolicy) {
      self.limit = limit
    }
  }

  private func cancel() {
    let handler = state.withCriticalRegion { state in
      // swap out the handler before we invoke it to prevent double cancel
      let handler = state.onTermination
      state.onTermination = nil
      return handler
    }

    // handler must be invoked before yielding nil for termination
    handler?(.cancelled)

    finish()
  }

  private func next(_ continuation: UnsafeContinuation<Element?, Never>) {
    let (continuation, toSend) = self.state.withCriticalRegion { state -> (UnsafeContinuation<Element?, Never>?, Element?) in
      state.continuations.append(continuation)
      if state.pending.count > 0 {
        return (state.continuations.removeFirst(), state.pending.removeFirst())
      } else if state.terminal {
        return (state.continuations.removeFirst(), nil)
      } else {
        return (nil, nil)
      }
    }
    continuation?.resume(returning: toSend)
  }
}

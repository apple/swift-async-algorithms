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
public final class AsyncThrowingSubject<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  public struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
    let subject: AsyncThrowingSubject<Element, Failure>
    private var active: Bool = true
    
    init(_ subject: AsyncThrowingSubject<Element, Failure>) {
      self.subject = subject
    }

    public mutating func next() async throws -> Element? {
      guard active else {
        return nil
      }

      do {
        let value = try await withTaskCancellationHandler {
          try await subject.next()
        } onCancel: { [subject] in
          subject.cancel()
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

  private let state: ManagedCriticalState<State>

  /// Create a new `AsyncThrowingSubject` given an element type.
  public init(element elementType: Element.Type = Element.self, bufferingPolicy limit: BufferingPolicy = .unbounded) where Failure == Error {
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
  /// normally or throw, based on a given result.
  ///
  /// - Parameter result: In the `.success(_:)` case, this returns the
  ///   associated value from the iterator's `next()` method. If the result
  ///   is the `failure(_:)` case, this call terminates the subject with
  ///   the result's error, by calling `finish(throwing:)`.
  /// - Returns: A `SendResult` that indicates the success or failure of the
  ///   send operation.
  ///
  /// If nothing is awaiting the next value and the result is success, this call
  /// attempts to buffer the result's element.
  ///
  /// If you call this method repeatedly, each call returns immediately, without
  /// blocking for any awaiting consumption from the iteration.
  @discardableResult
  public func send(with result: Result<Element, Failure>) -> SendResult where Failure == Error {
    switch result {
      case .success(let value):
        return send(value)
      case .failure(let error):
        fail(error)
        return .terminated
      }
  }

  /// Resume the task awaiting the next iteration point.
  ///
  /// - Parameter result: Returns the associated value from the iterator's
  ///   `next()` method.
  /// - Returns: A `SendResult` that indicates the success or failure of the
  ///   send operation.
  ///
  /// If nothing is awaiting the next value, this call attempts to buffer
  /// the result's element.
  ///
  /// If you call this method repeatedly, each call returns immediately, without
  /// blocking for any awaiting consumption from the iteration.
  @discardableResult
  public func send(_ element: Element) -> SendResult where Failure == Error {
    let (result, continuation) = state.withCriticalRegion { state -> (SendResult, (() -> Void)?) in
      var result: SendResult
      var c: (() -> Void)?
      let limit = state.limit
      let count = state.pending.count
      if let continuation = state.continuation {
        if count > 0 {
          if state.terminal == nil {
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
          state.continuation = nil
          let toSend = state.pending.removeFirst()
          c = {
            continuation.resume(returning: toSend)
          }
        } else if let terminal = state.terminal {
          result = .terminated
          state.continuation = nil
          state.terminal = .finished
          return (result, {
            switch terminal {
            case .finished:
              continuation.resume(returning: nil)
            case .failed(let error):
              continuation.resume(throwing: error)
            }
          })
        } else {
          switch limit {
          case .unbounded:
            result = .enqueued(remaining: .max)
          case .bufferingOldest(let limit):
            result = .enqueued(remaining: limit)
          case .bufferingNewest(let limit):
            result = .enqueued(remaining: limit)
          }

          state.continuation = nil
          c = {
            continuation.resume(returning: element)
          }
        }
      } else {
        if state.terminal == nil {
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
      }
      return (result, c)
    }
    continuation?()
    return result
  }

  /// Resume the task awaiting the next iteration point by having it return
  /// normally from its suspension point.
  ///
  /// - Returns: A `SendResult` that indicates the success or failure of the
  ///   send operation.
  ///
  /// Use this method with `AsyncThrowingSubject` instances whose `Element`
  /// type is `Void`. In this case, the `send()` call unblocks the
  /// awaiting iteration; there is no value to return.
  ///
  /// If you call this method repeatedly, each call returns immediately,
  /// without blocking for any awaiting consumption from the iteration.
  @discardableResult
  public func send() -> SendResult where Element == Void, Failure == Error {
    send(())
  }

  /// Send an error to all awaiting iterations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func fail(_ error: Failure) where Failure == Error {
    terminateAll(error: error)
  }

  /// Send a finish to all awaiting iterations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func finish() {
    terminateAll()
  }

  /// A callback to invoke when canceling iteration of an asynchronous
  /// stream.
  ///
  /// If an `onTermination` callback is set, using task cancellation to
  /// terminate iteration of an `AsyncThrowingSubject` results in a call to this
  /// callback.
  ///
  /// Canceling an active iteration invokes the `onTermination` callback
  /// first, and then resumes by yielding `nil` or throwing an error from the
  /// iterator. This means that you can perform needed cleanup in the
  ///  cancellation handler. After reaching a terminal state, the
  ///  `AsyncThrowingSubject` disposes of the callback.
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

  public func makeAsyncIterator() -> Iterator {
    Iterator(self)
  }
}

extension AsyncThrowingSubject {
  public enum Termination {
    /// The subject finished as a result of calling the `finish` method.
    ///
    ///  The associated `Failure` value provides the error that terminated
    ///  the subject. If no error occurred, this value is `nil`.
    case finished(Failure?)

    /// The subject finished as a result of cancellation.
    case cancelled
  }
}

extension AsyncThrowingSubject {
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

extension AsyncThrowingSubject {
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

extension AsyncThrowingSubject {
  fileprivate typealias TerminationHandler = @Sendable (Termination) -> Void

  fileprivate enum Terminal {
    case finished
    case failed(Failure)
  }

  fileprivate struct State: Sendable {
    var onTermination: TerminationHandler?
    var continuation: UnsafeContinuation<Element?, Error>?
    var pending = Deque<Element>()
    let limit: BufferingPolicy
    var terminal: Terminal?

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

  private func terminateAll(error: Failure? = nil) {
    state.withCriticalRegion { state in
      let handler = state.onTermination
      state.onTermination = nil
      if state.terminal == nil {
        if let failure = error {
          state.terminal = .failed(failure)
        } else {
          state.terminal = .finished
        }
      }
      if let continuation = state.continuation {
        if state.pending.count > 0 {
          state.continuation = nil
          let toSend = state.pending.removeFirst()
          return {
            handler?(.finished(error))
            continuation.resume(returning: toSend)
          }
        } else if let terminal = state.terminal {
          state.continuation = nil
          switch terminal {
          case .finished:
            return {
              handler?(.finished(error))
              continuation.resume(returning: nil)
            }
          case .failed(let error):
            return {
              handler?(.finished(error))
              continuation.resume(throwing: error)
            }
          }
        } else {
          return {
            handler?(.finished(error))
          }
        }
      } else {
        return {
          handler?(.finished(error))
        }
      }
    }()
  }

  private func next() async throws -> Element? {
    try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { continuation in
        next(continuation)
      }
    } onCancel: { [cancel] in
      cancel()
    }
  }

  private func next(_ continuation: UnsafeContinuation<Element?, Error>) {
    state.withCriticalRegion { state in
      if state.continuation == nil {
        if state.pending.count > 0 {
          let toSend = state.pending.removeFirst()
          return {
            continuation.resume(returning: toSend)
          }
        } else if let terminal = state.terminal {
          state.terminal = .finished
          return {
            switch terminal {
            case .finished:
              continuation.resume(returning: nil)
            case .failed(let error):
              continuation.resume(throwing: error)
            }
          }
        } else {
          state.continuation = continuation
          return { }
        }
      } else {
        fatalError("attempt to await next() on more than one task")
      }
    }()
  }
}

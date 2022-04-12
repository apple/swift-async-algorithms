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

actor AsyncBufferState<Input: Sendable, Output: Sendable> {
  enum TerminationState: Sendable, CustomStringConvertible {
    case running
    case baseFailure(Error) // An error from the base sequence has occurred. We need to process any buffered items before throwing the error. We can rely on it not emitting any more items.
    case baseTermination
    case terminal

    var description: String {
      switch self {
        case .running: return "running"
        case .baseFailure: return "base failure"
        case .baseTermination: return "base termination"
        case .terminal: return "terminal"
      }
    }
  }
  
  var pending = [UnsafeContinuation<Result<Output?, Error>, Never>]()
  var terminationState = TerminationState.running

  init() { }
  
  func drain<Buffer: AsyncBuffer>(buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    guard pending.count > 0 else {
      return
    }

    do {
      if let value = try await buffer.pop() {
        pending.removeFirst().resume(returning: .success(value))
      } else {
        switch terminationState {
          case .running:
            // There's no value to report, because it was probably grabbed by next() before we could grab it. The pending continuation was either resumed by next() directly, or will be by a future enqueued value or base termination/failure.
            break
          case .baseFailure(let error):
            // Now that there are no more items in the buffer, we can finally report the base sequence's error and enter terminal state.
            pending.removeFirst().resume(returning: .failure(error))
            self.terminate()
          case .terminal, .baseTermination:
            self.terminate()
        }
      }
    } catch {
      // Errors thrown by the buffer immediately terminate the sequence.
      pending.removeFirst().resume(returning: .failure(error))
      self.terminate()
    }
  }

  func enqueue<Buffer: AsyncBuffer>(_ item: Input, buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    await buffer.push(item)
    await drain(buffer: buffer)
  }
  
  func fail<Buffer: AsyncBuffer>(_ error: Error, buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    terminationState = .baseFailure(error)
    await drain(buffer: buffer)
  }
  
  func finish<Buffer: AsyncBuffer>(buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    if case .running = terminationState {
      terminationState = .baseTermination
    }
    await drain(buffer: buffer)
  }

  func terminate() {
    terminationState = .terminal
    let oldPending = pending
    pending = []
    for continuation in oldPending {
      continuation.resume(returning: .success(nil))
    }
  }

  func next<Buffer: AsyncBuffer>(buffer: Buffer) async throws -> Buffer.Output? where Buffer.Input == Input, Buffer.Output == Output {
    if case .terminal = terminationState {
      return nil
    }

    do {
      while let value = try await buffer.pop() {
        if let continuation = pending.first {
          pending.removeFirst()
          continuation.resume(returning: .success(value))
        } else {
          return value
        }
      }
    } catch {
      // Errors thrown by the buffer immediately terminate the sequence.
      self.terminate()
      throw error
    }

    switch terminationState {
      case .running:
        break
      case .baseFailure(let error):
        self.terminate()
        throw error
      case .baseTermination, .terminal:
        self.terminate()
        return nil
    }

    let result: Result<Output?, Error> = await withUnsafeContinuation { continuation in
      pending.append(continuation)
    }
    return try result._rethrowGet()
  }
}

/// An asynchronous buffer storage actor protocol used for buffering
/// elements to an `AsyncBufferSequence`.
@rethrows
public protocol AsyncBuffer: Actor {
  associatedtype Input: Sendable
  associatedtype Output: Sendable

  /// Push an element to enqueue to the buffer
  func push(_ element: Input) async
  
  /// Pop an element from the buffer.
  ///
  /// Implementors of `pop()` may throw. In cases where types
  /// throw from this function, that throwing behavior contributes to
  /// the rethrowing characteristics of `AsyncBufferSequence`.
  func pop() async throws -> Output?
}

/// A buffer that limits pushed items by a certain count.
public actor AsyncLimitBuffer<Element: Sendable>: AsyncBuffer {
  /// A policy for buffering elements to an `AsyncLimitBuffer`
  public enum Policy: Sendable {
    /// A policy for no bounding limit of pushed elements.
    case unbounded
    /// A policy for limiting to a specific number of oldest values.
    case bufferingOldest(Int)
    /// A policy for limiting to a specific number of newest values.
    case bufferingNewest(Int)
  }
  
  var buffer = [Element]()
  let policy: Policy
  
  init(policy: Policy) {
    // limits should always be greater than 0 items
    switch policy {
      case .bufferingNewest(let limit):
        precondition(limit > 0)
      case .bufferingOldest(let limit):
        precondition(limit > 0)
      default: break
    }
    self.policy = policy
  }
  
  /// Push an element to enqueue to the buffer.
  public func push(_ element: Element) async {
    switch policy {
    case .unbounded:
      buffer.append(element)
    case .bufferingOldest(let limit):
      if buffer.count < limit {
        buffer.append(element)
      }
    case .bufferingNewest(let limit):
      if buffer.count < limit {
        // there is space available
        buffer.append(element)
      } else {
        // no space is available and this should make some room
        buffer.removeFirst()
        buffer.append(element)
      }
    }
  }
  
  /// Pop an element from the buffer.
  public func pop() async -> Element? {
    guard buffer.count > 0 else {
      return nil
    }
    return buffer.removeFirst()
  }
}

extension AsyncSequence where Element: Sendable {
  /// Creates an asynchronous sequence that buffers elements using a buffer created from a supplied closure.
  ///
  /// Use the `buffer(_:)` method to account for `AsyncSequence` types that may produce elements faster
  /// than they are iterated. The `createBuffer` closure returns a backing buffer for storing elements and dealing with
  /// behavioral characteristics of the `buffer(_:)` algorithm.
  ///
  /// - Parameter createBuffer: A closure that constructs a new `AsyncBuffer` actor to store buffered values.
  /// - Returns: An asynchronous sequence that buffers elements using the specified `AsyncBuffer`.
  public func buffer<Buffer: AsyncBuffer>(_ createBuffer: @Sendable @escaping () -> Buffer) -> AsyncBufferSequence<Self, Buffer> where Buffer.Input == Element {
    AsyncBufferSequence(self, createBuffer: createBuffer)
  }
  
  /// Creates an asynchronous sequence that buffers elements using a specific policy to limit the number of
  /// elements that are buffered.
  ///
  /// - Parameter policy: A limiting policy behavior on the buffering behavior of the `AsyncBufferSequence`
  /// - Returns: An asynchronous sequence that buffers elements up to a given limit.
  public func buffer(policy limit: AsyncLimitBuffer<Element>.Policy) -> AsyncBufferSequence<Self, AsyncLimitBuffer<Element>> {
    buffer {
      AsyncLimitBuffer(policy: limit)
    }
  }
}

/// An `AsyncSequence` that buffers elements utilizing an `AsyncBuffer`.
public struct AsyncBufferSequence<Base: AsyncSequence, Buffer: AsyncBuffer> where Base.Element == Buffer.Input, Base.AsyncIterator: Sendable {
  let base: Base
  let createBuffer: @Sendable () -> Buffer
  
  init(_ base: Base, createBuffer: @Sendable @escaping () -> Buffer) {
    self.base = base
    self.createBuffer = createBuffer
  }
}

extension AsyncBufferSequence: Sendable where Base: Sendable { }
extension AsyncBufferSequence.Iterator: Sendable where Base: Sendable { }

extension AsyncBufferSequence: AsyncSequence {
  public typealias Element = Buffer.Output
  
  /// The iterator for a `AsyncBufferSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {
    struct Active {
      var task: Task<Void, Never>?
      let buffer: Buffer
      let state: AsyncBufferState<Buffer.Input, Buffer.Output>
      
      init(_ iterator: Base.AsyncIterator, buffer: Buffer, state: AsyncBufferState<Buffer.Input, Buffer.Output>) {
        self.buffer = buffer
        self.state = state
        task = Task {
          var iter = iterator
          do {
            while let item = try await iter.next() {
              await state.enqueue(item, buffer: buffer)
            }
            await state.finish(buffer: buffer)
          } catch {
            await state.fail(error, buffer: buffer)
          }
        }
      }
      
      func next() async rethrows -> Element? {
        let result: Result<Element?, Error> = await withTaskCancellationHandler {
          task?.cancel()
        } operation: {
          do {
            let value = try await state.next(buffer: buffer)
            return .success(value)
          } catch {
            task?.cancel()
            return .failure(error)
          }
        }
        return try result._rethrowGet()
      }
    }
    
    enum State {
      case idle(Base.AsyncIterator, @Sendable () -> Buffer)
      case active(Active)
    }
    
    var state: State
    
    init(_ iterator: Base.AsyncIterator, createBuffer: @Sendable @escaping () -> Buffer) {
      state = .idle(iterator, createBuffer)
    }
    
    public mutating func next() async rethrows -> Element? {
      switch state {
      case .idle(let iterator, let createBuffer):
        let bufferState = AsyncBufferState<Base.Element, Buffer.Output>()
        let buffer = Active(iterator, buffer: createBuffer(), state: bufferState)
        state = .active(buffer)
        return try await buffer.next()
      case .active(let buffer):
        return try await buffer.next()
      }
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator(), createBuffer: createBuffer)
  }
}

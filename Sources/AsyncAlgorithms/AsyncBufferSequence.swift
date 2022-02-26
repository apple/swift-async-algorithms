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

internal struct AsyncBufferState<Input, Output> : Sendable {
  enum Continuation: CustomStringConvertible {
    case idle
    case placeholder
    case pending(UnsafeContinuation<Result<Output?, Error>, Never>)
    case resolved(Result<Output?, Error>)
    
    var description: String {
      switch self {
      case .idle: return "idle"
      case .placeholder:
        return "placeholder"
      case .resolved:
        return "resolved"
      case .pending:
        return "pending"
      }
    }
  }
  
  struct State {
    var pending = Continuation.idle
    var generation = 0
    var finished = false
    var failure: Error?
  }
  
  let state = ManagedCriticalState(State())
  
  init() { }
  
  func drain<Buffer: AsyncBuffer>(buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    let pending = state.withCriticalRegion { $0.pending }
    switch pending {
    case .idle:
      return
    case .pending(let continuation):
      do {
        if let value = try await buffer.pop() {
          state.withCriticalRegion { $0.pending = .idle }
          continuation.resume(returning: .success(value))
        } else {
          state.withCriticalRegion { state in
            if let error = state.failure {
              state.failure = nil
              state.pending = .resolved(.failure(error))
            } else if state.finished {
              state.pending = .resolved(.success(nil))
            }
          }
        }
      } catch {
        state.withCriticalRegion { $0.pending = .idle }
        continuation.resume(returning: .failure(error))
      }
    case .placeholder:
      do {
        if let value = try await buffer.pop() {
          state.withCriticalRegion { state in
            state.pending = .resolved(.success(value))
          }
        } else {
          state.withCriticalRegion { state in
            if let error = state.failure {
              state.failure = nil
              state.pending = .resolved(.failure(error))
            } else if state.finished {
              state.pending = .resolved(.success(nil))
            }
          }
        }
      } catch {
        state.withCriticalRegion { state in
          state.pending = .resolved(.failure(error))
        }
      }
    case .resolved:
      break
    }
  }
  
  func enqueue<Buffer: AsyncBuffer>(_ item: Input, buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    await buffer.push(item)
    await drain(buffer: buffer)
  }
  
  func fail<Buffer: AsyncBuffer>(_ error: Error, buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    state.withCriticalRegion { state in
      state.finished = true
      state.failure = error
    }
    await drain(buffer: buffer)
  }
  
  func finish<Buffer: AsyncBuffer>(buffer: Buffer) async where Buffer.Input == Input, Buffer.Output == Output {
    state.withCriticalRegion { state in
      state.finished = true
    }
    await drain(buffer: buffer)
  }
  
  func next<Buffer: AsyncBuffer>(buffer: Buffer) async throws -> Buffer.Output? where Buffer.Input == Input, Buffer.Output == Output {
    state.withCriticalRegion { $0.pending = .placeholder }
    do {
      if let value = try await buffer.pop() {
        state.withCriticalRegion { $0.pending = .idle }
        return value
      }
    } catch {
      state.withCriticalRegion { $0.pending = .idle }
      await fail(error, buffer: buffer)
      throw error
    }
    var other: UnsafeContinuation<Result<Output?, Error>, Never>?
    let result: Result<Output?, Error> = await withUnsafeContinuation { continuation in
      state.withCriticalRegion { state -> UnsafeResumption<Result<Output?, Error>, Never>? in
        if let error = state.failure {
          state.failure = nil
          return UnsafeResumption(continuation: continuation, success: .failure(error))
        } else if state.finished {
          return UnsafeResumption(continuation: continuation, success: .success(nil))
        } else {
          switch state.pending {
          case .placeholder:
            state.pending = .pending(continuation)
            return nil
          case .resolved(let result):
            state.pending = .idle
            return UnsafeResumption(continuation: continuation, success: result)
          case .idle:
            state.pending = .pending(continuation)
            return nil
          case .pending(let existing):
            other = existing
            state.pending = .pending(continuation)
            return nil
          }
        }
      }?.resume()
    }
    other?.resume(returning: result)
    return try result._rethrowGet()
  }
}

@rethrows
public protocol AsyncBuffer: Sendable {
  associatedtype Input
  associatedtype Output

  func push(_ element: Input) async
  func pop() async throws -> Output?
}

public actor AsyncLimitBuffer<Element: Sendable>: AsyncBuffer {
  public enum Policy : Sendable {
    case unbounded
    case bufferingOldest(Int)
    case bufferingNewest(Int)
  }
  
  var buffer = [Element]()
  let policy: Policy
  
  init(policy: Policy) {
    self.policy = policy
  }
  
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
        buffer.append(element)
      } else if buffer.count > 0 {
        buffer.removeFirst()
        buffer.append(element)
      }
    }
  }
  
  public func pop() async -> Element? {
    guard buffer.count > 0 else {
      return nil
    }
    return buffer.removeFirst()
  }
}

extension AsyncSequence where Element: Sendable {
  public func buffer<Buffer: AsyncBuffer>(_ createBuffer: @Sendable @escaping () -> Buffer) -> AsyncBufferSequence<Self, Buffer> where Buffer.Input == Element {
    AsyncBufferSequence(self, createBuffer: createBuffer)
  }
  
  public func buffer(bufferingPolicy limit: AsyncLimitBuffer<Element>.Policy = .unbounded) -> AsyncBufferSequence<Self, AsyncLimitBuffer<Element>> {
    buffer {
      AsyncLimitBuffer(policy: limit)
    }
  }
}

public struct AsyncBufferSequence<Base: AsyncSequence, Buffer: AsyncBuffer> where Base.Element == Buffer.Input {
  let base: Base
  let createBuffer: @Sendable () -> Buffer
  
  init(_ base: Base, createBuffer: @Sendable @escaping () -> Buffer) {
    self.base = base
    self.createBuffer = createBuffer
  }
}

extension AsyncBufferSequence: AsyncSequence {
  public typealias Element = Buffer.Output
  
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

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

public final class AsyncThrowingSubject<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let subject: AsyncThrowingSubject<Element, Failure>
    var active: Bool = true
    
    init(_ subject: AsyncThrowingSubject<Element, Failure>) {
      self.subject = subject
    }
    
    public mutating func next() async throws -> Element? {
      guard active else {
        return nil
      }
      let generation = subject.establish()
      do {
        let value: Element? = try await withTaskCancellationHandler { [subject] in
            subject.cancel(generation)
        } operation: {
          try await subject.next(generation)
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
    
    init(generation: Int, continuation: UnsafeContinuation<Element?, Error>) {
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
    
    static func == (_ lhs: Awaiting, _ rhs: Awaiting) -> Bool {
      return lhs.generation == rhs.generation
    }
  }
  
  enum Emission {
    case initial
    case pending([UnsafeContinuation<UnsafeContinuation<Element?, Error>?, Never>])
    case awaiting(Set<Awaiting>)
    
    mutating func remove(_ generation: Int) -> UnsafeContinuation<Element?, Error>? {
      switch self {
      case .awaiting(var awaiting):
        let continuation = awaiting.remove(Awaiting(placeholder: generation))?.continuation
        self = .awaiting(awaiting)
        return continuation
      default:
        return nil
      }
    }
  }
  
  struct State {
    var emission: Emission = .initial
    var generation = 0
    var terminal = false
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
      state.emission.remove(generation)
    }?.resume(returning: nil)
  }
  
  func next(_ generation: Int) async throws -> Element? {
    return try await withUnsafeThrowingContinuation { continuation in
      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Error>?, Never>? in
        switch state.emission {
        case .initial:
          state.emission = .awaiting([Awaiting(generation: generation, continuation: continuation)])
          return nil
        case .pending(var sends):
          let send = sends.removeFirst()
          if sends.count == 0 {
            state.emission = .initial
          } else {
            state.emission = .pending(sends)
          }
          return UnsafeResumption(continuation: send, success: continuation)
        case .awaiting(var nexts):
          nexts.insert(Awaiting(generation: generation, continuation: continuation))
          state.emission = .awaiting(nexts)
          return nil
        }
      }?.resume()
    }
  }
  
  func _send(_ result: Result<Element?, Error>) async {
    let continuation: UnsafeContinuation<Element?, Error>? = await withUnsafeContinuation { continuation in
      state.withCriticalRegion { state -> UnsafeResumption<UnsafeContinuation<Element?, Error>?, Never>? in
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
        case .initial:
          state.emission = .pending([continuation])
          return nil
        case .pending(var sends):
          sends.append(continuation)
          state.emission = .pending(sends)
          return nil
        case .awaiting(var nexts):
          let next = nexts.removeFirst().continuation
          if nexts.count == 0 {
            state.emission = .initial
          } else {
            state.emission = .awaiting(nexts)
          }
          return UnsafeResumption(continuation: continuation, success: next)
        }
      }?.resume()
    }
    continuation?.resume(with: result)
  }
  
  public func send(_ element: Element) async {
      await _send(.success(element))
  }
  
  public func fail(_ error: Error) async where Failure == Error {
    await _send(.failure(error))
  }
  
  public func finish() async {
      await _send(.success(nil))
  }
  
  public func makeAsyncIterator() -> Iterator {
    return Iterator(self)
  }
}

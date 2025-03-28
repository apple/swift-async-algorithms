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

import AsyncAlgorithms

public struct Validator<Element: Sendable>: Sendable {
  private enum Ready {
    case idle
    case ready
    case pending(UnsafeContinuation<Void, Never>)
  }

  private struct State: Sendable {
    var collected = [Element]()
    var failure: Error?
    var ready: Ready = .idle
  }

  private struct Envelope<Contents>: @unchecked Sendable {
    var contents: Contents
  }

  private let state = ManagedCriticalState(State())

  private func ready(_ apply: (inout State) -> Void) {
    state.withCriticalRegion { state -> UnsafeContinuation<Void, Never>? in
      apply(&state)
      switch state.ready {
      case .idle:
        state.ready = .ready
        return nil
      case .pending(let continuation):
        state.ready = .idle
        return continuation
      case .ready:
        return nil
      }
    }?.resume()
  }

  internal func step() async {
    await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
      state.withCriticalRegion { state -> UnsafeContinuation<Void, Never>? in
        switch state.ready {
        case .ready:
          state.ready = .idle
          return continuation
        case .idle:
          state.ready = .pending(continuation)
          return nil
        case .pending:
          fatalError()
        }
      }?.resume()
    }
  }

  let onEvent: (@Sendable (Result<Element?, Error>) async -> Void)?

  init(onEvent: @Sendable @escaping (Result<Element?, Error>) async -> Void) {

    self.onEvent = onEvent
  }

  public init() {
    self.onEvent = nil
  }

  public func test<S: AsyncSequence>(
    _ sequence: S,
    onFinish: @Sendable @escaping (inout S.AsyncIterator) async -> Void
  ) where S.Element == Element {
    let envelope = Envelope(contents: sequence)
    Task {
      var iterator = envelope.contents.makeAsyncIterator()
      ready { _ in }
      do {
        while let item = try await iterator.next() {
          await onEvent?(.success(item))
          ready { state in
            state.collected.append(item)
          }
        }
        await onEvent?(.success(nil))
      } catch {
        await onEvent?(.failure(error))
        ready { state in
          state.failure = error
        }
      }
      ready { _ in }
      await onFinish(&iterator)
    }
  }

  public func validate() async -> [Element] {
    await step()
    return current
  }

  public var current: [Element] {
    return state.withCriticalRegion { state in
      return state.collected
    }
  }

  public var failure: Error? {
    return state.withCriticalRegion { state in
      return state.failure
    }
  }
}

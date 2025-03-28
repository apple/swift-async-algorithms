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

public struct Gate: Sendable {
  enum State {
    case closed
    case open
    case pending(UnsafeContinuation<Void, Never>)
  }

  let state = ManagedCriticalState(State.closed)

  public func `open`() {
    state.withCriticalRegion { state -> UnsafeContinuation<Void, Never>? in
      switch state {
      case .closed:
        state = .open
        return nil
      case .open:
        return nil
      case .pending(let continuation):
        state = .closed
        return continuation
      }
    }?.resume()
  }

  public func enter() async {
    var other: UnsafeContinuation<Void, Never>?
    await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
      state.withCriticalRegion { state -> UnsafeContinuation<Void, Never>? in
        switch state {
        case .closed:
          state = .pending(continuation)
          return nil
        case .open:
          state = .closed
          return continuation
        case .pending(let existing):
          other = existing
          state = .pending(continuation)
          return nil
        }
      }?.resume()
    }
    other?.resume()
  }
}

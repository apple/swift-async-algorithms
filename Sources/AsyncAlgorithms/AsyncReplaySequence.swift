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

public extension AsyncSequence {
  func replay(count: Int) -> AsyncReplaySequence<Self> {
    AsyncReplaySequence(base: self, count: count)
  }
}

public struct AsyncReplaySequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  private let base: Base
  private let count: Int
  private let history: ManagedCriticalState<Deque<Result<Base.Element?, Error>>>

  public init(base: Base, count: Int) {
    self.base = base
    self.count = count
    self.history = ManagedCriticalState([])
  }

  private func push(element: Result<Element?, Error>) {
    self.history.withCriticalRegion { history in
      if history.count >= count {
        _ = history.popFirst()
      }
      history.append(element)
    }
  }

  private func dumpHistory(into localHistory: inout Deque<Result<Base.Element?, Error>>?) {
    self.history.withCriticalRegion { localHistory = $0 }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    return Iterator(
      asyncReplaySequence: self,
      base: self.base.makeAsyncIterator()
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let asyncReplaySequence: AsyncReplaySequence<Base>
    var base: Base.AsyncIterator
    var history: Deque<Result<Base.Element?, Error>>?

    public mutating func next() async rethrows -> Element? {
      if self.history == nil {
        // first call to next, we make sure we have the latest available history
        self.asyncReplaySequence.dumpHistory(into: &self.history)
      }

      if self.history!.isEmpty {
        // nothing to replay, we request the next element from the base and push it in the history
        let element: Result<Base.Element?, Error>
        do {
          element = .success(try await self.base.next())
        } catch {
          element = .failure(error)
        }

        self.asyncReplaySequence.push(element: element)
        return try element._rethrowGet()
      } else {
        guard !Task.isCancelled else { return nil }

        // we replay the oldest element from the history
        let element = self.history!.popFirst()!
        return try element._rethrowGet()
      }
    }
  }
}

extension AsyncReplaySequence: Sendable where Base: Sendable, Base.Element: Sendable { }

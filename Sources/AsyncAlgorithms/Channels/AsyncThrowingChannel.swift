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

/// An error-throwing channel for sending elements from on task to another with back pressure.
///
/// The `AsyncThrowingChannel` class is intended to be used as a communication types between tasks,
/// particularly when one task produces values and another task consumes those values. The back
/// pressure applied by `send(_:)` via suspension/resume ensures that the production of values does
/// not exceed the consumption of values from iteration. This method suspends after enqueuing the event
/// and is resumed when the next call to `next()` on the `Iterator` is made, or when `finish()`/`fail(_:)` is called
/// from another Task. As `finish()` and `fail(_:)` induce a terminal state, there is no more need for a back pressure management.
/// Those functions do not suspend and will finish all the pending iterations.
@available(AsyncAlgorithms 1.0, *)
public final class AsyncThrowingChannel<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  let storage: ChannelStorage<Element, Failure>

  public init() {
    self.storage = ChannelStorage()
  }

  /// Sends an element to an awaiting iteration. This function will resume when the next call to `next()` is made
  /// or when a call to `finish()` or `fail` is made from another task.
  /// If the channel is already finished then this returns immediately.
  /// If the task is cancelled, this function will resume without sending the element.
  /// Other sending operations from other tasks will remain active.
  public func send(_ element: Element) async {
    await self.storage.send(element: element)
  }

  /// Sends an error to all awaiting iterations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func fail(_ error: Error) where Failure == Error {
    self.storage.finish(error: error)
  }

  /// Immediately resumes all the suspended operations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  public func finish() {
    self.storage.finish()
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(storage: self.storage)
  }

  public struct Iterator: AsyncIteratorProtocol {
    let storage: ChannelStorage<Element, Failure>

    public mutating func next() async throws -> Element? {
      try await self.storage.next()
    }
  }
}

@available(*, unavailable)
extension AsyncThrowingChannel.Iterator: Sendable {}

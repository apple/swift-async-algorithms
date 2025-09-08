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

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequence where Self: Sendable {
  /// Creates an asynchronous sequence that buffers elements.
  ///
  /// The buffering behaviour is dictated by the policy:
  /// - bounded: will buffer elements until the limit is reached. Then it will suspend the upstream async sequence.
  /// - unbounded: will buffer elements without limit.
  /// - bufferingNewest: will buffer elements until the limit is reached. Then it will discard the oldest elements.
  /// - bufferingOldest: will buffer elements until the limit is reached. Then it will discard the newest elements.
  ///
  /// - Parameter policy: A policy that drives the behaviour of the ``AsyncBufferSequence``
  /// - Returns: An asynchronous sequence that buffers elements up to a given limit.
  @available(AsyncAlgorithms 1.0, *)
  public func buffer(
    policy: AsyncBufferSequencePolicy
  ) -> AsyncBufferSequence<Self> {
    AsyncBufferSequence<Self>(base: self, policy: policy)
  }
}

/// A policy dictating the buffering behaviour of an ``AsyncBufferSequence``
@available(AsyncAlgorithms 1.0, *)
public struct AsyncBufferSequencePolicy: Sendable {
  enum _Policy {
    case bounded(Int)
    case unbounded
    case bufferingNewest(Int)
    case bufferingOldest(Int)
  }

  let policy: _Policy

  /// A policy for buffering elements until the limit is reached.
  /// Then consumption of the upstream `AsyncSequence` will be paused until elements are consumed from the buffer.
  /// If the limit is zero then no buffering policy is applied.
  public static func bounded(_ limit: Int) -> Self {
    precondition(limit >= 0, "The limit should be positive or equal to 0.")
    return Self(policy: .bounded(limit))
  }

  /// A policy for buffering elements without limit.
  public static var unbounded: Self {
    return Self(policy: .unbounded)
  }

  /// A policy for buffering elements until the limit is reached.
  /// After the limit is reached and a new element is produced by the upstream, the oldest buffered element will be discarded.
  /// If the limit is zero then no buffering policy is applied.
  public static func bufferingLatest(_ limit: Int) -> Self {
    precondition(limit >= 0, "The limit should be positive or equal to 0.")
    return Self(policy: .bufferingNewest(limit))
  }

  /// A policy for buffering elements until the limit is reached.
  /// After the limit is reached and a new element is produced by the upstream, the latest buffered element will be discarded.
  /// If the limit is zero then no buffering policy is applied.
  public static func bufferingOldest(_ limit: Int) -> Self {
    precondition(limit >= 0, "The limit should be positive or equal to 0.")
    return Self(policy: .bufferingOldest(limit))
  }
}

/// An `AsyncSequence` that buffers elements in regard to a policy.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncBufferSequence<Base: AsyncSequence & Sendable>: AsyncSequence {
  // Internal implementation note:
  // This type origianlly had no requirement that the element is actually Sendable. However,
  // that is technically an implementation detail hole in the safety of the system, it needs
  // to specify that the element is actually Sendable since the draining mechanism passes
  // through the isolation that is in nature sending but cannot be marked as such for the
  // isolated next method.
  // In practice the users of this type are safe from isolation crossing since the Element
  // is as sendable as it is required by the base sequences the buffer is constructed from.
  enum StorageType {
    case transparent(Base.AsyncIterator)
    case bounded(storage: BoundedBufferStorage<Base>)
    case unbounded(storage: UnboundedBufferStorage<Base>)
  }

  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  let base: Base
  let policy: AsyncBufferSequencePolicy

  init(
    base: Base,
    policy: AsyncBufferSequencePolicy
  ) {
    self.base = base
    self.policy = policy
  }

  public func makeAsyncIterator() -> Iterator {
    let storageType: StorageType
    switch self.policy.policy {
    case .bounded(...0), .bufferingNewest(...0), .bufferingOldest(...0):
      storageType = .transparent(self.base.makeAsyncIterator())
    case .bounded(let limit):
      storageType = .bounded(storage: BoundedBufferStorage(base: self.base, limit: limit))
    case .unbounded:
      storageType = .unbounded(storage: UnboundedBufferStorage(base: self.base, policy: .unlimited))
    case .bufferingNewest(let limit):
      storageType = .unbounded(storage: UnboundedBufferStorage(base: self.base, policy: .bufferingNewest(limit)))
    case .bufferingOldest(let limit):
      storageType = .unbounded(storage: UnboundedBufferStorage(base: self.base, policy: .bufferingOldest(limit)))
    }
    return Iterator(storageType: storageType)
  }

  public struct Iterator: AsyncIteratorProtocol {
    var storageType: StorageType

    public mutating func next() async rethrows -> Element? {
      switch self.storageType {
      case .transparent(var iterator):
        let element = try await iterator.next()
        self.storageType = .transparent(iterator)
        return element
      case .bounded(let storage):
        return try await storage.next().wrapped?._rethrowGet()
      case .unbounded(let storage):
        return try await storage.next().wrapped?._rethrowGet()
      }
    }
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncBufferSequence: Sendable where Base: Sendable {}

@available(*, unavailable)
extension AsyncBufferSequence.Iterator: Sendable {}

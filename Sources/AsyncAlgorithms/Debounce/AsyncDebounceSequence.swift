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
extension AsyncSequence {
  /// Creates an asynchronous sequence that emits the latest element after a given quiescence period
  /// has elapsed by using a specified Clock.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func debounce<C: Clock>(
    for interval: C.Instant.Duration,
    tolerance: C.Instant.Duration? = nil,
    clock: C
  ) -> AsyncDebounceSequence<Self, C> where Self: Sendable, Self.Element: Sendable {
    AsyncDebounceSequence(self, interval: interval, tolerance: tolerance, clock: clock)
  }

  /// Creates an asynchronous sequence that emits the latest element after a given quiescence period
  /// has elapsed.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func debounce(
    for interval: Duration,
    tolerance: Duration? = nil
  ) -> AsyncDebounceSequence<Self, ContinuousClock> where Self: Sendable, Self.Element: Sendable {
    self.debounce(for: interval, tolerance: tolerance, clock: .continuous)
  }
}

/// An `AsyncSequence` that emits the latest element after a given quiescence period
/// has elapsed.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AsyncDebounceSequence<Base: AsyncSequence & Sendable, C: Clock>: Sendable where Base.Element: Sendable {
  private let base: Base
  private let clock: C
  private let interval: C.Instant.Duration
  private let tolerance: C.Instant.Duration?

  /// Initializes a new ``AsyncDebounceSequence``.
  ///
  /// - Parameters:
  ///   - base: The base sequence.
  ///   - interval: The interval to debounce.
  ///   - tolerance: The tolerance of the clock.
  ///   - clock: The clock.
  init(_ base: Base, interval: C.Instant.Duration, tolerance: C.Instant.Duration?, clock: C) {
    self.base = base
    self.interval = interval
    self.tolerance = tolerance
    self.clock = clock
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncDebounceSequence: AsyncSequence {
  public typealias Element = Base.Element

  public func makeAsyncIterator() -> Iterator {
    let storage = DebounceStorage(
      base: self.base,
      interval: self.interval,
      tolerance: self.tolerance,
      clock: self.clock
    )
    return Iterator(storage: storage)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncDebounceSequence {
  public struct Iterator: AsyncIteratorProtocol {
    /// This class is needed to hook the deinit to observe once all references to the ``AsyncIterator`` are dropped.
    ///
    /// If we get move-only types we should be able to drop this class and use the `deinit` of the ``AsyncIterator`` struct itself.
    final class InternalClass: Sendable {
      private let storage: DebounceStorage<Base, C>

      fileprivate init(storage: DebounceStorage<Base, C>) {
        self.storage = storage
      }

      deinit {
        self.storage.iteratorDeinitialized()
      }

      func next() async rethrows -> Element? {
        try await self.storage.next()
      }
    }

    let internalClass: InternalClass

    fileprivate init(storage: DebounceStorage<Base, C>) {
      self.internalClass = InternalClass(storage: storage)
    }

    public mutating func next() async rethrows -> Element? {
      try await self.internalClass.next()
    }
  }
}

@available(*, unavailable)
extension AsyncDebounceSequence.Iterator: Sendable {}

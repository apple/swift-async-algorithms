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

extension AsyncSequence {
  /// Creates an asynchronous sequence that emits the latest element after a given quiescence period
  /// has elapsed by using a specified Clock.
  @available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
  public func debounce<C: Clock>(for interval: C.Instant.Duration, tolerance: C.Instant.Duration? = nil, clock: C) -> AsyncDebounceSequence<Self, C> {
    AsyncDebounceSequence(self, interval: interval, tolerance: tolerance, clock: clock)
  }
  
  /// Creates an asynchronous sequence that emits the latest element after a given quiescence period
  /// has elapsed.
  @available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
  public func debounce(for interval: Duration, tolerance: Duration? = nil) -> AsyncDebounceSequence<Self, ContinuousClock> {
    debounce(for: interval, tolerance: tolerance, clock: .continuous)
  }
}

/// An `AsyncSequence` that emits the latest element after a given quiescence period
/// has elapsed.
@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
public struct AsyncDebounceSequence<Base: AsyncSequence, C: Clock>: Sendable
  where Base.AsyncIterator: Sendable, Base.Element: Sendable, Base: Sendable {
  let base: Base
  let interval: C.Instant.Duration
  let tolerance: C.Instant.Duration?
  let clock: C
  
  init(_ base: Base, interval: C.Instant.Duration, tolerance: C.Instant.Duration?, clock: C) {
    self.base = base
    self.interval = interval
    self.tolerance = tolerance
    self.clock = clock
  }
}

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
extension AsyncDebounceSequence: AsyncSequence {
  public typealias Element = Base.Element
  
  /// The iterator for a `AsyncDebounceSequence` instance.
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    enum Partial: Sendable {
      case sleep
      case produce(Result<Base.Element?, Error>, Base.AsyncIterator)
    }
    var iterator: Base.AsyncIterator
    var produce: Task<Partial, Never>?
    var terminal = false
    let interval: C.Instant.Duration
    let tolerance: C.Instant.Duration?
    let clock: C
    
    init(_ base: Base.AsyncIterator, interval: C.Instant.Duration, tolerance: C.Instant.Duration?, clock: C) {
      self.iterator = base
      self.interval = interval
      self.tolerance = tolerance
      self.clock = clock
    }
    
    public mutating func next() async rethrows -> Base.Element? {
      var last: C.Instant?
      var lastResult: Result<Element?, Error>?
      while !terminal {
        let deadline = (last ?? clock.now).advanced(by: interval)
        let sleep: Task<Partial, Never> = Task { [tolerance, clock] in
          try? await clock.sleep(until: deadline, tolerance: tolerance)
          return .sleep
        }
        let produce: Task<Partial, Never> = self.produce ?? Task { [iterator] in
          var iter = iterator
          do {
            let value = try await iter.next()
            return .produce(.success(value), iter)
          } catch {
            return .produce(.failure(error), iter)
          }
        }
        self.produce = nil
        switch await Task.select(sleep, produce).value {
        case .sleep:
          self.produce = produce
          if let result = lastResult {
            return try result._rethrowGet()
          }
          break
        case .produce(let result, let iter):
          lastResult = result
          last = clock.now
          sleep.cancel()
          self.iterator = iter
          switch result {
          case .success(let value):
            if value == nil {
              terminal = true
              return nil
            }
          case .failure:
            terminal = true
            try result._rethrowError()
          }
          break
        }
      }
      return nil
    }
  }
  
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator(), interval: interval, tolerance: tolerance, clock: clock)
  }
}

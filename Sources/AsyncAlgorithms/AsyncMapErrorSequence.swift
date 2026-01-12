//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.0)
@available(AsyncAlgorithms 1.2, *)
extension AsyncSequence {

  /// Converts any failure into a new error.
  ///
  /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
  /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
  ///
  /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
  @available(AsyncAlgorithms 1.2, *)
  public func mapError<MappedError: Error>(
    _ transform: @Sendable @escaping (Self.Failure) -> MappedError
  ) -> some AsyncSequence<Self.Element, MappedError> {
    AsyncMapErrorSequence(base: self, transform: transform)
  }

  /// Converts any failure into a new error.
  ///
  /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
  /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
  ///
  /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
  @available(AsyncAlgorithms 1.2, *)
  public func mapError<MappedError: Error>(
    _ transform: @Sendable @escaping (Self.Failure) -> MappedError
  ) -> (some AsyncSequence<Self.Element, MappedError> & Sendable) where Self: Sendable, Self.Element: Sendable {
    AsyncMapErrorSequence(base: self, transform: transform)
  }
}

/// An asynchronous sequence that converts any failure into a new error.
@available(AsyncAlgorithms 1.2, *)
struct AsyncMapErrorSequence<Base: AsyncSequence, MappedError: Error> {
  typealias Element = Base.Element
  typealias Failure = MappedError

  private let base: Base
  private let transform: @Sendable (Base.Failure) async -> MappedError

  init(
    base: Base,
    transform: @Sendable @escaping (Base.Failure) async -> MappedError
  ) {
    self.base = base
    self.transform = transform
  }
}

@available(AsyncAlgorithms 1.2, *)
extension AsyncMapErrorSequence: AsyncSequence {

  /// The iterator that produces elements of the map sequence.
  struct Iterator: AsyncIteratorProtocol {
    typealias Element = Base.Element

    private var base: Base.AsyncIterator

    private let transform: @Sendable (Base.Failure) async -> MappedError

    init(
      base: Base.AsyncIterator,
      transform: @Sendable @escaping (Base.Failure) async -> MappedError
    ) {
      self.base = base
      self.transform = transform
    }

    mutating func next() async throws(MappedError) -> Element? {
      try await self.next(isolation: nil)
    }

    mutating func next(isolation actor: isolated (any Actor)?) async throws(MappedError) -> Element? {
      do {
        return try await base.next(isolation: actor)
      } catch {
        throw await transform(error)
      }
    }
  }

  func makeAsyncIterator() -> Iterator {
    Iterator(
      base: base.makeAsyncIterator(),
      transform: transform
    )
  }
}

@available(AsyncAlgorithms 1.2, *)
extension AsyncMapErrorSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncMapErrorSequence.Iterator: Sendable {}
#endif

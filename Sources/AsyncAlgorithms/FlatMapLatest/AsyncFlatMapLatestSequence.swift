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

@available(AsyncAlgorithms 1.1, *)
extension AsyncSequence where Self: Sendable {
  /// Transforms elements into new asynchronous sequences, emitting elements
  /// from the most recent inner sequence.
  ///
  /// When a new element is emitted by this sequence, the `transform`
  /// is called to produce a new inner sequence. Iteration on the
  /// previous inner sequence is cancelled, and iteration begins
  /// on the new one.
  
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> some AsyncSequence<T.Element, T.Failure> & Sendable where T.Failure == Failure, T.Element: Sendable, Element: Sendable {
    return AsyncFlatMapLatestSequence(self, transform: transform)
  }

  @_disfavoredOverload
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> some AsyncSequence<T.Element, Failure> & Sendable where T.Failure == Never, T.Element: Sendable, Element: Sendable {
    return AsyncFlatMapLatestSequence(self) {
      transform($0).mapError { _ -> Failure in
        fatalError()
      }
    }
  }

  @_disfavoredOverload
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> some AsyncSequence<T.Element, T.Failure> & Sendable where Failure == Never, T.Element: Sendable, Element: Sendable {
    return AsyncFlatMapLatestSequence(self.mapError { _ -> T.Failure in
      fatalError()
    }, transform: transform)
  }
}

@available(AsyncAlgorithms 1.1, *)
struct AsyncFlatMapLatestSequence<Base: AsyncSequence & Sendable, Inner: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable, Inner.Element: Sendable, Base.Failure == Inner.Failure{
  typealias Element = Inner.Element
  typealias Failure = Inner.Failure

  let base: Base
  let transform: @Sendable (Base.Element) -> Inner
  
  init(_ base: Base, transform: @escaping @Sendable (Base.Element) -> Inner) {
    self.base = base
    self.transform = transform
  }
  
  func makeAsyncIterator() -> Iterator {
    return Iterator(base: base, transform: transform)
  }
  
  struct Iterator: AsyncIteratorProtocol, Sendable {
    let storage: FlatMapLatestStorage<Base, Inner>
    
    init(base: Base, transform: @escaping @Sendable (Base.Element) -> Inner) {
      self.storage = FlatMapLatestStorage(base: base, transform: transform)
    }

    func next(isolation: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
      return try await storage.next(isolation: isolation)
    }
  }
}

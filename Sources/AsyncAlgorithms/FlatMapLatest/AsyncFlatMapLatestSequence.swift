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
  /// Transforms elements into new asynchronous sequences, emitting elements
  /// from the most recent inner sequence.
  ///
  /// When a new element is emitted by this sequence, the `transform`
  /// is called to produce a new inner sequence. Iteration on the
  /// previous inner sequence is cancelled, and iteration begins
  /// on the new one.
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> AsyncFlatMapLatestSequence<Self, T> {
    return AsyncFlatMapLatestSequence(self, transform: transform)
  }
}

@available(AsyncAlgorithms 1.0, *)
public struct AsyncFlatMapLatestSequence<Base: AsyncSequence & Sendable, Inner: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable, Inner.Element: Sendable {
  public typealias Element = Inner.Element
  
  let base: Base
  let transform: @Sendable (Base.Element) -> Inner
  
  init(_ base: Base, transform: @escaping @Sendable (Base.Element) -> Inner) {
    self.base = base
    self.transform = transform
  }
  
  public func makeAsyncIterator() -> Iterator {
    return Iterator(base: base, transform: transform)
  }
  
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let storage: FlatMapLatestStorage<Base, Inner>
    
    init(base: Base, transform: @escaping @Sendable (Base.Element) -> Inner) {
      self.storage = FlatMapLatestStorage(base: base, transform: transform)
    }
    
    public func next() async throws -> Element? {
      return try await storage.next()
    }
  }
}

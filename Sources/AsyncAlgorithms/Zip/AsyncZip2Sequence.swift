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

/// Creates an asynchronous sequence that concurrently awaits values from two `AsyncSequence` types
/// and emits a tuple of the values.
public func zip<Base1: AsyncSequence, Base2: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2
) -> AsyncZip2Sequence<Base1, Base2> {
  AsyncZip2Sequence(base1, base2)
}

/// An asynchronous sequence that concurrently awaits values from two `AsyncSequence` types
/// and emits a tuple of the values.
public struct AsyncZip2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: AsyncSequence
  where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable {
  public typealias Element = (Base1.Element, Base2.Element)
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2

  init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base1Iterator: self.base1.makeAsyncIterator(),
      base2Iterator: self.base2.makeAsyncIterator()
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    /// Typealias for the result of the task group that consumes the upstreams.
    private typealias Results = (
      first: (iterator: Base1.AsyncIterator, element: Base1.Element?)?,
      second: (iterator: Base2.AsyncIterator, element: Base2.Element?)?
    )

    /// The iterator of the first base.
    private var base1Iterator: Base1.AsyncIterator
    /// The iterator of the second base.
    private var base2Iterator: Base2.AsyncIterator
    /// Boolean indicating if we already finished. The transition to finished happens if one of the upstreams returned nil or threw
    private var isFinished = false

    init(base1Iterator: Base1.AsyncIterator, base2Iterator: Base2.AsyncIterator) {
      self.base1Iterator = base1Iterator
      self.base2Iterator = base2Iterator
    }

    public mutating func next() async rethrows -> Element? {
      // Check if we are already finished and exit early
      if self.isFinished {
        return nil
      }

      // We need to take a copy of the base iterators since we cannot concurrently modify
      // self in the task group. We are going to mutate each iterator in a separate child task
      // and in the end store them in self again.
      let iterator1 = self.base1Iterator
      let iterator2 = self.base2Iterator

      do {
        let results: Results? = try await withThrowingTaskGroup(of: Results?.self) { group in
          group.addTask {
            var iterator = iterator1
            let element = try await iterator.next()
            return ((iterator, element), nil)
          }

          group.addTask {
            var iterator = iterator2
            let element = try await iterator.next()
            return (nil, (iterator, element))
          }

          var results: Results = (nil, nil)

          for try await result in group {
            if let first = result!.first {
              if first.element == nil {
                return nil
              } else {
                results.first = first
              }
            } else if let second = result!.second {
              if second.element == nil {
                return nil
              } else {
                results.second = second
              }
            }
          }

          return results
        }

        guard let results = results else {
          // One of the upstreams
          self.isFinished = true
          return nil
        }

        // Updating the iterators again after they have been mutated
        // The force unwraps are safe here since all upstreams either need to return something or throw
        self.base1Iterator = results.first!.iterator
        self.base2Iterator = results.second!.iterator

        return (results.first!.element!, results.second!.element!)
      } catch {
        // One of the upstreams thew an error. Let's transition to finished and rethrow it
        self.isFinished = true
        throw error
      }
    }
  }
}

@available(*, unavailable)
extension AsyncZip2Sequence.Iterator: Sendable {}

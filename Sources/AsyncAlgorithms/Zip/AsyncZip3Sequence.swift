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

/// Creates an asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
public func zip<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2,
  _ base3: Base3
) -> AsyncZip3Sequence<Base1, Base2, Base3> {
  AsyncZip3Sequence(base1, base2, base3)
}

/// An asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
public struct AsyncZip3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: AsyncSequence
  where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable, Base3: Sendable, Base3.Element: Sendable {
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2
  let base3: Base3

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base1Iterator: self.base1.makeAsyncIterator(),
      base2Iterator: self.base2.makeAsyncIterator(),
      base3Iterator: self.base3.makeAsyncIterator()
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    /// Typealias for the result of the task group that consumes the upstreams.
    private typealias Results = (
      first: (iterator: Base1.AsyncIterator, element: Base1.Element?)?,
      second: (iterator: Base2.AsyncIterator, element: Base2.Element?)?,
      third: (iterator: Base3.AsyncIterator, element: Base3.Element?)?
    )

    /// The iterator of the first base.
    private var base1Iterator: Base1.AsyncIterator
    /// The iterator of the second base.
    private var base2Iterator: Base2.AsyncIterator
    /// The iterator of the third base.
    private var base3Iterator: Base3.AsyncIterator
    /// Boolean indicating if we already finished. The transition to finished happens if one of the upstreams returned nil or threw
    private var isFinished = false

    init(base1Iterator: Base1.AsyncIterator, base2Iterator: Base2.AsyncIterator, base3Iterator: Base3.AsyncIterator) {
      self.base1Iterator = base1Iterator
      self.base2Iterator = base2Iterator
      self.base3Iterator = base3Iterator
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
      let iterator3 = self.base3Iterator

      do {
        let results: Results? = try await withThrowingTaskGroup(of: Results?.self) { group in
          group.addTask {
            var iterator = iterator1
            let element = try await iterator.next()
            return ((iterator, element), nil, nil)
          }

          group.addTask {
            var iterator = iterator2
            let element = try await iterator.next()
            return (nil, (iterator, element), nil)
          }

          group.addTask {
            var iterator = iterator3
            let element = try await iterator.next()
            return (nil, nil, (iterator, element))
          }

          var results: Results = (nil, nil, nil)

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

            } else if let third = result!.third {
              if third.element == nil {
                return nil
              } else {
                results.third = third
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
        self.base3Iterator = results.third!.iterator

        return (results.first!.element!, results.second!.element!, results.third!.element!)
      } catch {
        // One of the upstreams thew an error. Let's transition to finished and rethrow it
        self.isFinished = true
        throw error
      }
    }
  }
}

@available(*, unavailable)
extension AsyncZip3Sequence.Iterator: Sendable {}

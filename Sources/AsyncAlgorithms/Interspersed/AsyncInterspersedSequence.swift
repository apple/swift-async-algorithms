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
  /// Returns a new asynchronous sequence containing the elements of this asynchronous sequence, inserting
  /// the given separator between each element.
  ///
  /// Any value of this asynchronous sequence's element type can be used as the separator.
  ///
  /// The following example shows how an async sequences of `String`s can be interspersed using `-` as the separator:
  /// 
  /// ```
  /// let input = ["A", "B", "C"].async
  /// let interspersed = input.interspersed(with: "-")
  /// for await element in interspersed {
  ///   print(element)
  /// }
  /// // Prints "A" "-" "B" "-" "C"
  /// ```
  ///
  /// - Parameter separator: The value to insert in between each of this async
  ///   sequence’s elements.
  /// - Returns: The interspersed asynchronous sequence of elements.
  @inlinable
  public func interspersed(with separator: Element) -> AsyncInterspersedSequence<Self> {
    AsyncInterspersedSequence(self, separator: separator)
  }
}

/// An asynchronous sequence that presents the elements of a base asynchronous sequence of
/// elements with a separator between each of those elements.
public struct AsyncInterspersedSequence<Base: AsyncSequence> {
  @usableFromInline
  internal let base: Base

  @usableFromInline
  internal let separator: Base.Element

  @usableFromInline
  init(_ base: Base, separator: Base.Element) {
    self.base = base
    self.separator = separator
  }
}

extension AsyncInterspersedSequence: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncInterspersedSequence` asynchronous sequence.
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    internal enum State {
      case start
      case element(Result<Base.Element, Error>)
      case separator
    }

    @usableFromInline
    internal var iterator: Base.AsyncIterator

    @usableFromInline
    internal let separator: Base.Element

    @usableFromInline
    internal var state = State.start

    @usableFromInline
    init(_ iterator: Base.AsyncIterator, separator: Base.Element) {
      self.iterator = iterator
      self.separator = separator
    }

    public mutating func next() async rethrows -> Base.Element? {
      // After the start, the state flips between element and separator. Before
      // returning a separator, a check is made for the next element as a
      // separator is only returned between two elements. The next element is
      // stored to allow it to be returned in the next iteration. However, if
      // the checking the next element throws, the separator is emitted before
      // rethrowing that error.
      switch state {
        case .start:
          state = .separator
          return try await iterator.next()
        case .separator:
          do {
            guard let next = try await iterator.next() else { return nil }
            state = .element(.success(next))
          } catch {
            state = .element(.failure(error))
          }
          return separator
        case .element(let result):
          state = .separator
          return try result._rethrowGet()
      }
    }
  }

  @inlinable
  public func makeAsyncIterator() -> AsyncInterspersedSequence<Base>.Iterator {
      Iterator(base.makeAsyncIterator(), separator: separator)
  }
}

extension AsyncInterspersedSequence: Sendable where Base: Sendable, Base.Element: Sendable { }

@available(*, unavailable)
extension AsyncInterspersedSequence.Iterator: Sendable {}

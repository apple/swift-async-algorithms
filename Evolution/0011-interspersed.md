# Feature name

* Proposal: [SAA-0011](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0011-interspersed.md)
* Authors: [Philippe Hausler](https://github.com/phausler)
* Review Manager: [Franz Busch](https://github.com/FranzBusch)
* Status: **Implemented**

* Implementation: 
  [Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Interspersed/AsyncInterspersedSequence.swift) | 
  [Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestLazy.swift)

## Motivation

A common transformation that is applied to async sequences is to intersperse the elements with
a separator element.

## Proposed solution

We propose to add a new method on `AsyncSequence` that allows to intersperse
a separator between each emitted element. This proposed API looks like this

```swift
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
```

## Detailed design

The bulk of the implementation of the new `interspersed` method is inside the new 
`AsyncInterspersedSequence` struct. It constructs an iterator to the base async sequence
inside its own iterator. The `AsyncInterspersedSequence.Iterator.next()` is forwarding the demand
to the base iterator.
There is one special case that we have to call out. When the base async sequence throws
then `AsyncInterspersedSequence.Iterator.next()` will return the separator first and then rethrow the error.

Below is the implementation of the `AsyncInterspersedSequence`.
```swift
/// An asynchronous sequence that presents the elements of a base asynchronous sequence of
/// elements with a separator between each of those elements.
public struct AsyncInterspersedSequence<Base: AsyncSequence> {
  @usableFromInline
  internal let base: Base

  @usableFromInline
  internal let separator: Base.Element

  @usableFromInline
  internal init(_ base: Base, separator: Base.Element) {
    self.base = base
    self.separator = separator
  }
}

extension AsyncInterspersedSequence: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncInterspersedSequence` asynchronous sequence.
  public struct AsyncIterator: AsyncIteratorProtocol {
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
    internal init(_ iterator: Base.AsyncIterator, separator: Base.Element) {
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
  public func makeAsyncIterator() -> AsyncInterspersedSequence<Base>.AsyncIterator {
        AsyncIterator(base.makeAsyncIterator(), separator: separator)
  }
}
```

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
a separator between every n emitted element. This proposed API looks like this

```swift
public extension AsyncSequence {
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
    /// - Parameters:
    ///   - every: Dictates after how many elements a separator should be inserted.
    ///   - separator: The value to insert in between each of this async sequence’s elements.
    /// - Returns: The interspersed asynchronous sequence of elements.
    @inlinable
    func interspersed(every: Int = 1, with separator: Element) -> AsyncInterspersedSequence<Self> {
        AsyncInterspersedSequence(self, every: every, separator: separator)
    }

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
    /// - Parameters:
    ///   - every: Dictates after how many elements a separator should be inserted.
    ///   - separator: A closure that produces the value to insert in between each of this async sequence’s elements.
    /// - Returns: The interspersed asynchronous sequence of elements.
    @inlinable
    func interspersed(every: Int = 1, with separator: @Sendable @escaping () -> Element) -> AsyncInterspersedSequence<Self> {
        AsyncInterspersedSequence(self, every: every, separator: separator)
    }

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
    /// - Parameters:
    ///   - every: Dictates after how many elements a separator should be inserted.
    ///   - separator: A closure that produces the value to insert in between each of this async sequence’s elements.
    /// - Returns: The interspersed asynchronous sequence of elements.
    @inlinable
    func interspersed(every: Int = 1, with separator: @Sendable @escaping () async -> Element) -> AsyncInterspersedSequence<Self> {
        AsyncInterspersedSequence(self, every: every, separator: separator)
    }
    
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
    /// - Parameters:
    ///   - every: Dictates after how many elements a separator should be inserted.
    ///   - separator: A closure that produces the value to insert in between each of this async sequence’s elements.
    /// - Returns: The interspersed asynchronous sequence of elements.
    @inlinable
    public func interspersed(every: Int = 1, with separator: @Sendable @escaping () throws -> Element) -> AsyncThrowingInterspersedSequence<Self> {
        AsyncThrowingInterspersedSequence(self, every: every, separator: separator)
    }

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
    /// - Parameters:
    ///   - every: Dictates after how many elements a separator should be inserted.
    ///   - separator: A closure that produces the value to insert in between each of this async sequence’s elements.
    /// - Returns: The interspersed asynchronous sequence of elements.
    @inlinable
    public func interspersed(every: Int = 1, with separator: @Sendable @escaping () async throws -> Element) -> AsyncThrowingInterspersedSequence<Self> {
        AsyncThrowingInterspersedSequence(self, every: every, separator: separator)
    }
}
```

## Detailed design

The bulk of the implementation of the new `interspersed` method is inside the new 
`AsyncInterspersedSequence` struct. It constructs an iterator to the base async sequence
inside its own iterator. The `AsyncInterspersedSequence.Iterator.next()` is forwarding the demand
to the base iterator.

Below is the implementation of the `AsyncInterspersedSequence`.
```swift
/// An asynchronous sequence that presents the elements of a base asynchronous sequence of
/// elements with a separator between each of those elements.
public struct AsyncInterspersedSequence<Base: AsyncSequence> {
    @usableFromInline
    internal enum Separator {
        case element(Element)
        case syncClosure(@Sendable () -> Element)
        case asyncClosure(@Sendable () async -> Element)
    }

    @usableFromInline
    internal let base: Base

    @usableFromInline
    internal let separator: Separator

    @usableFromInline
    internal let every: Int

    @usableFromInline
    internal init(_ base: Base, every: Int, separator: Element) {
        precondition(every > 0, "Separators can only be interspersed every 1+ elements")
        self.base = base
        self.separator = .element(separator)
        self.every = every
    }

    @usableFromInline
    internal init(_ base: Base, every: Int, separator: @Sendable @escaping () -> Element) {
        precondition(every > 0, "Separators can only be interspersed every 1+ elements")
        self.base = base
        self.separator = .syncClosure(separator)
        self.every = every
    }

    @usableFromInline
    internal init(_ base: Base, every: Int, separator: @Sendable @escaping () async -> Element) {
        precondition(every > 0, "Separators can only be interspersed every 1+ elements")
        self.base = base
        self.separator = .asyncClosure(separator)
        self.every = every
    }
}

extension AsyncInterspersedSequence: AsyncSequence {
    public typealias Element = Base.Element

    /// The iterator for an `AsyncInterspersedSequence` asynchronous sequence.
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        internal enum State {
            case start(Element?)
            case element(Int)
            case separator
            case finished
        }

        @usableFromInline
        internal var iterator: Base.AsyncIterator

        @usableFromInline
        internal let separator: Separator

        @usableFromInline
        internal let every: Int

        @usableFromInline
        internal var state = State.start(nil)

        @usableFromInline
        internal init(_ iterator: Base.AsyncIterator, every: Int, separator: Separator) {
            self.iterator = iterator
            self.separator = separator
            self.every = every
        }

        public mutating func next() async rethrows -> Base.Element? {
            // After the start, the state flips between element and separator. Before
            // returning a separator, a check is made for the next element as a
            // separator is only returned between two elements. The next element is
            // stored to allow it to be returned in the next iteration. However, if
            // the checking the next element throws, the separator is emitted before
            // rethrowing that error.
            switch state {
            case var .start(element):
                do {
                    if element == nil {
                        element = try await self.iterator.next()
                    }

                    if let element = element {
                        if every == 1 {
                            state = .separator
                        } else {
                            state = .element(1)
                        }
                        return element
                    } else {
                        state = .finished
                        return nil
                    }
                } catch {
                    state = .finished
                    throw error
                }

            case .separator:
                do {
                    if let element = try await iterator.next() {
                        state = .start(element)
                        switch separator {
                        case let .element(element):
                            return element

                        case let .syncClosure(closure):
                            return closure()

                        case let .asyncClosure(closure):
                            return await closure()
                        }
                    } else {
                        state = .finished
                        return nil
                    }
                } catch {
                    state = .finished
                    throw error
                }

            case let .element(count):
                do {
                    if let element = try await iterator.next() {
                        let newCount = count + 1
                        if every == newCount {
                            state = .separator
                        } else {
                            state = .element(newCount)
                        }
                        return element
                    } else {
                        state = .finished
                        return nil
                    }
                } catch {
                    state = .finished
                    throw error
                }

            case .finished:
                return nil
            }
        }
    }

    @inlinable
    public func makeAsyncIterator() -> AsyncInterspersedSequence<Base>.Iterator {
        Iterator(base.makeAsyncIterator(), every: every, separator: separator)
    }
}
```

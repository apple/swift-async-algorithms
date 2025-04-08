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
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func interspersed(every: Int = 1, with separator: Element) -> AsyncInterspersedSequence<Self> {
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
  /// let interspersed = input.interspersed(with: { "-" })
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
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func interspersed(
    every: Int = 1,
    with separator: @Sendable @escaping () -> Element
  ) -> AsyncInterspersedSequence<Self> {
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
  /// let interspersed = input.interspersed(with: { "-" })
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
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func interspersed(
    every: Int = 1,
    with separator: @Sendable @escaping () async -> Element
  ) -> AsyncInterspersedSequence<Self> {
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
  /// let interspersed = input.interspersed(with: { "-" })
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
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func interspersed(
    every: Int = 1,
    with separator: @Sendable @escaping () throws -> Element
  ) -> AsyncThrowingInterspersedSequence<Self> {
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
  /// let interspersed = input.interspersed(with: { "-" })
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
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func interspersed(
    every: Int = 1,
    with separator: @Sendable @escaping () async throws -> Element
  ) -> AsyncThrowingInterspersedSequence<Self> {
    AsyncThrowingInterspersedSequence(self, every: every, separator: separator)
  }
}

/// An asynchronous sequence that presents the elements of a base asynchronous sequence of
/// elements with a separator between each of those elements.
@available(AsyncAlgorithms 1.0, *)
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

@available(AsyncAlgorithms 1.0, *)
extension AsyncInterspersedSequence: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncInterspersedSequence` asynchronous sequence.
  @available(AsyncAlgorithms 1.0, *)
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
      switch self.state {
      case .start(var element):
        do {
          if element == nil {
            element = try await self.iterator.next()
          }

          guard let element = element else {
            self.state = .finished
            return nil
          }
          if self.every == 1 {
            self.state = .separator
          } else {
            self.state = .element(1)
          }
          return element
        } catch {
          self.state = .finished
          throw error
        }

      case .separator:
        do {
          guard let element = try await iterator.next() else {
            self.state = .finished
            return nil
          }
          self.state = .start(element)
          switch self.separator {
          case .element(let element):
            return element

          case .syncClosure(let closure):
            return closure()

          case .asyncClosure(let closure):
            return await closure()
          }
        } catch {
          self.state = .finished
          throw error
        }

      case .element(let count):
        do {
          guard let element = try await iterator.next() else {
            self.state = .finished
            return nil
          }
          let newCount = count + 1
          if self.every == newCount {
            self.state = .separator
          } else {
            self.state = .element(newCount)
          }
          return element
        } catch {
          self.state = .finished
          throw error
        }

      case .finished:
        return nil
      }
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(self.base.makeAsyncIterator(), every: self.every, separator: self.separator)
  }
}

/// An asynchronous sequence that presents the elements of a base asynchronous sequence of
/// elements with a separator between each of those elements.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncThrowingInterspersedSequence<Base: AsyncSequence> {
  @usableFromInline
  internal enum Separator {
    case syncClosure(@Sendable () throws -> Element)
    case asyncClosure(@Sendable () async throws -> Element)
  }

  @usableFromInline
  internal let base: Base

  @usableFromInline
  internal let separator: Separator

  @usableFromInline
  internal let every: Int

  @usableFromInline
  internal init(_ base: Base, every: Int, separator: @Sendable @escaping () throws -> Element) {
    precondition(every > 0, "Separators can only be interspersed every 1+ elements")
    self.base = base
    self.separator = .syncClosure(separator)
    self.every = every
  }

  @usableFromInline
  internal init(_ base: Base, every: Int, separator: @Sendable @escaping () async throws -> Element) {
    precondition(every > 0, "Separators can only be interspersed every 1+ elements")
    self.base = base
    self.separator = .asyncClosure(separator)
    self.every = every
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncThrowingInterspersedSequence: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncInterspersedSequence` asynchronous sequence.
  @available(AsyncAlgorithms 1.0, *)
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

    public mutating func next() async throws -> Base.Element? {
      switch self.state {
      case .start(var element):
        do {
          if element == nil {
            element = try await self.iterator.next()
          }

          guard let element = element else {
            self.state = .finished
            return nil
          }
          if self.every == 1 {
            self.state = .separator
          } else {
            self.state = .element(1)
          }
          return element
        } catch {
          self.state = .finished
          throw error
        }

      case .separator:
        do {
          guard let element = try await iterator.next() else {
            self.state = .finished
            return nil
          }
          self.state = .start(element)
          switch self.separator {
          case .syncClosure(let closure):
            return try closure()

          case .asyncClosure(let closure):
            return try await closure()
          }
        } catch {
          self.state = .finished
          throw error
        }

      case .element(let count):
        do {
          guard let element = try await iterator.next() else {
            self.state = .finished
            return nil
          }
          let newCount = count + 1
          if self.every == newCount {
            self.state = .separator
          } else {
            self.state = .element(newCount)
          }
          return element
        } catch {
          self.state = .finished
          throw error
        }

      case .finished:
        return nil
      }
    }
  }

  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(self.base.makeAsyncIterator(), every: self.every, separator: self.separator)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncInterspersedSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
@available(AsyncAlgorithms 1.0, *)
extension AsyncInterspersedSequence.Separator: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(AsyncAlgorithms 1.0, *)
extension AsyncThrowingInterspersedSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
@available(AsyncAlgorithms 1.0, *)
extension AsyncThrowingInterspersedSequence.Separator: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncInterspersedSequence.Iterator: Sendable {}
@available(*, unavailable)
extension AsyncThrowingInterspersedSequence.Iterator: Sendable {}

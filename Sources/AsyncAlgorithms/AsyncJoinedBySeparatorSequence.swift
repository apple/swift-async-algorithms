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
extension AsyncSequence where Element: AsyncSequence {
  /// Concatenate an `AsyncSequence` of `AsyncSequence` elements with a separator.
  @available(AsyncAlgorithms 1.0, *)
  @inlinable
  public func joined<Separator: AsyncSequence>(
    separator: Separator
  ) -> AsyncJoinedBySeparatorSequence<Self, Separator> {
    return AsyncJoinedBySeparatorSequence(self, separator: separator)
  }
}

/// An `AsyncSequence` that concatenates `AsyncSequence` elements with a separator.
@available(AsyncAlgorithms 1.0, *)
public struct AsyncJoinedBySeparatorSequence<Base: AsyncSequence, Separator: AsyncSequence>: AsyncSequence
where Base.Element: AsyncSequence, Separator.Element == Base.Element.Element {
  public typealias Element = Base.Element.Element
  public typealias AsyncIterator = Iterator

  /// The iterator for an `AsyncJoinedBySeparatorSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    enum State {
      @usableFromInline
      enum SeparatorState {
        case initial(Separator)
        case partialAsync(Separator.AsyncIterator, ContiguousArray<Element>)
        case cached(ContiguousArray<Element>)
        case partialCached(ContiguousArray<Element>.Iterator, ContiguousArray<Element>)

        @usableFromInline
        func startSeparator() -> SeparatorState {
          switch self {
          case .initial(let separatorSequence):
            return .partialAsync(separatorSequence.makeAsyncIterator(), [])
          case .cached(let array):
            return .partialCached(array.makeIterator(), array)
          default:
            fatalError("Invalid separator sequence state")
          }
        }

        @usableFromInline
        func next() async rethrows -> (Element?, SeparatorState) {
          switch self {
          case .partialAsync(var separatorIterator, var cache):
            guard let next = try await separatorIterator.next() else {
              return (nil, .cached(cache))
            }
            cache.append(next)
            return (next, .partialAsync(separatorIterator, cache))
          case .partialCached(var cacheIterator, let cache):
            guard let next = cacheIterator.next() else {
              return (nil, .cached(cache))
            }
            return (next, .partialCached(cacheIterator, cache))
          default:
            fatalError("Invalid separator sequence state")
          }
        }
      }

      case initial(Base.AsyncIterator, Separator)
      case sequence(Base.AsyncIterator, Base.Element.AsyncIterator, SeparatorState)
      case separator(Base.AsyncIterator, SeparatorState, Base.Element)
      case terminal
    }

    @usableFromInline
    var state: State

    @usableFromInline
    init(_ iterator: Base.AsyncIterator, separator: Separator) {
      state = .initial(iterator, separator)
    }

    @inlinable
    public mutating func next() async rethrows -> Base.Element.Element? {
      do {
        switch state {
        case .terminal:
          return nil
        case .initial(var outerIterator, let separator):
          guard let innerSequence = try await outerIterator.next() else {
            state = .terminal
            return nil
          }
          let innerIterator = innerSequence.makeAsyncIterator()
          state = .sequence(outerIterator, innerIterator, .initial(separator))
          return try await next()
        case .sequence(var outerIterator, var innerIterator, let separatorState):
          if let item = try await innerIterator.next() {
            state = .sequence(outerIterator, innerIterator, separatorState)
            return item
          }

          guard let nextInner = try await outerIterator.next() else {
            state = .terminal
            return nil
          }

          state = .separator(outerIterator, separatorState.startSeparator(), nextInner)
          return try await next()
        case .separator(let iterator, let separatorState, let nextBase):
          let (itemOpt, newSepState) = try await separatorState.next()
          guard let item = itemOpt else {
            state = .sequence(iterator, nextBase.makeAsyncIterator(), newSepState)
            return try await next()
          }
          state = .separator(iterator, newSepState, nextBase)
          return item
        }
      } catch {
        state = .terminal
        throw error
      }
    }
  }

  @usableFromInline
  let base: Base

  @usableFromInline
  let separator: Separator

  @usableFromInline
  init(_ base: Base, separator: Separator) {
    self.base = base
    self.separator = separator
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    return Iterator(base.makeAsyncIterator(), separator: separator)
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncJoinedBySeparatorSequence: Sendable
where Base: Sendable, Base.Element: Sendable, Base.Element.Element: Sendable, Separator: Sendable {}

@available(*, unavailable)
extension AsyncJoinedBySeparatorSequence.Iterator: Sendable {}

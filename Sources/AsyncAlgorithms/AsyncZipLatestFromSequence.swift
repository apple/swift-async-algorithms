//
//  AsyncZipLatestSequence.swift
//  
//
//  Created by Thibault Wittemberg on 31/03/2022.
//

public extension AsyncSequence {
  /// Combines `self` with another ``AsyncSequence`` into a single ``AsyncSequence`` where each
  /// element from `self` is aggregated to the latest known element from the `other` sequence (if any) as a tuple.
  ///
  /// Remark: as the `other` sequence is being iterated over in the context of its own ``Task``, there is no guarantee
  /// that its latest know element is the one that has just been produced when the base sequence produces its next element.
  ///
  /// ```
  /// let base = AsyncChannel<Int>()
  /// let other = AsyncChannel<String>()
  /// let sequence = base.zipLatest(from: other)
  ///
  /// Task {
  ///   for element in await sequence {
  ///    print(element)
  ///   }
  /// }
  ///
  /// await other.send("a")
  /// await other.send("b")
  ///
  /// ... later in the application flow
  ///
  /// await base.send(1)
  ///
  /// // will print: (1, "b")
  /// ```
  ///
  /// - Parameter other: the other ``AsyncSequence``
  /// - Returns: an ``AsyncZipLatestFromSequence`` where elements are a tuple of an element from `self` and the
  /// latest known element (if any) from the `other` sequence.
  func zipLatest<Other: AsyncSequence>(
    from other: Other
  ) -> AsyncZipLatestFromSequence<Self, Other> {
    AsyncZipLatestFromSequence(self, other)
  }

  /// Combines `self` with two other ``AsyncSequence`` into a single ``AsyncSequence`` where each
  /// element from `self` is aggregated to the latest known elements from the `other` sequences (if any) as a tuple.
  ///
  /// Remark: as the `other` sequences are being iterated over in the context of their own ``Task``, there is no guarantee
  /// that their latest know elements are the ones that have just been produced when the base sequence produces its next element.
  ///
  /// ```
  /// let base = AsyncChannel<Int>()
  /// let other1 = AsyncChannel<String>()
  /// let other2 = AsyncChannel<String>()
  /// let sequence = base.zipLatest(from: other1, other2)
  ///
  /// Task {
  ///   for element in await sequence {
  ///    print(element)
  ///   }
  /// }
  ///
  /// await other1.send("a")
  /// await other1.send("b")
  ///
  /// await other2.send("c")
  /// await other2.send("d")
  ///
  /// ... later in the application flow
  ///
  /// await base.send(1)
  ///
  /// // will print: (1, "b", "d")
  /// ```
  ///
  /// - Parameters:
  ///   - other1: the first other ``AsyncSequence``
  ///   - other2: the second other ``AsyncSequence``
  /// - Returns: an ``AsyncZipLatestFrom2Sequence`` where elements are a tuple of an element from `self` and the
  /// latest known elements (if any) from the `other` sequences.
  func zipLatest<Other1: AsyncSequence, Other2: AsyncSequence>(
    from other1: Other1,
    _ other2: Other2
  ) -> AsyncZipLatestFrom2Sequence<Self, Other1, Other2> {
    AsyncZipLatestFrom2Sequence(self, other1, other2)
  }
}

/// ``AsyncZipLatestFromSequence`` is an ``AsyncSequence`` where elements are a tuple of an element from `base` and the
/// latest known element (if any) from the `other` sequence.
public struct AsyncZipLatestFromSequence<Base: AsyncSequence, Other: AsyncSequence>: AsyncSequence, Sendable
where Base: Sendable,
      Base.AsyncIterator: Sendable,
      Base.Element: Sendable,
      Other: Sendable,
      Other.AsyncIterator: Sendable,
      Other.Element: Sendable {
  public typealias Element = (Base.Element, Other.Element)
  public typealias AsyncIterator = Iterator

  let base: Base
  let other: AsyncCurrentElementSequence<Other>

  /// Creates an ``AsyncSequence`` where elements are a tuple of an element from `base` and the
  /// latest known element (if any) from the `other` sequence.
  /// - Parameters:
  ///   - base: the ``AsyncSequence`` that drives the production of the output tuples
  ///   - other: the ``AsyncSequence`` from which the latest known element is gathered to form the output tuple
  public init(_ base: Base, _ other: Other) {
    self.base = base
    self.other = AsyncCurrentElementSequence(other)
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      self.base.makeAsyncIterator(),
      self.other.makeAsyncIterator()
    )
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    var base: Base.AsyncIterator
    var other: AsyncCurrentElementSequence<Other>.AsyncIterator
    var isFinished = false

    init(_ base: Base.AsyncIterator, _ other: AsyncCurrentElementSequence<Other>.AsyncIterator) {
      self.base = base
      self.other = other
    }

    public mutating func next() async rethrows -> Element? {
      guard !self.isFinished else { return nil }

      var baseElement: Base.Element?
      var lastKnownOtherState: AsyncCurrentElementSequence<Other>.State?

      var hasElementFromOther = false
      var hasOtherFinished = false

      repeat {
        guard !Task.isCancelled else {
          self.other.task.cancel()
          return nil
        }

        do {
          baseElement = try await self.base.next()
        } catch {
          self.other.task.cancel()
          throw error
        }
        
        lastKnownOtherState = await self.other.next()

        switch lastKnownOtherState {
        case .none: hasOtherFinished = true
        case .some(.noElement): hasElementFromOther = false
        case .some(.element): hasElementFromOther = true
        case .some(.finished): break
        }

      } while !hasElementFromOther && !hasOtherFinished

      guard let nonNilOtherState = lastKnownOtherState, case let .element(otherResult) = nonNilOtherState else {
        self.isFinished = true
        return nil
      }

      guard let nonNilBaseElement = baseElement else {
        self.other.task.cancel()
        self.isFinished = true
        return nil
      }

      return (nonNilBaseElement, try otherResult._rethrowGet())
    }
  }
}

/// ``AsyncZipLatestFrom2Sequence`` is an ``AsyncSequence`` where elements are a tuple of an element from `base` and the
/// latest known elements (if any) from the other sequences.
public struct AsyncZipLatestFrom2Sequence<Base: AsyncSequence, Other1: AsyncSequence, Other2: AsyncSequence>: AsyncSequence, Sendable
where Base: Sendable,
      Base.AsyncIterator: Sendable,
      Base.Element: Sendable,
      Other1: Sendable,
      Other1.AsyncIterator: Sendable,
      Other1.Element: Sendable,
      Other2: Sendable,
      Other2.AsyncIterator: Sendable,
      Other2.Element: Sendable {
  public typealias Element = (Base.Element, Other1.Element, Other2.Element)
  public typealias AsyncIterator = Iterator

  let base: Base
  let other1: AsyncCurrentElementSequence<Other1>
  let other2: AsyncCurrentElementSequence<Other2>

  /// Creates an ``AsyncSequence`` where elements are a tuple of an element from `base` and the
  /// latest known elements (if any) from the `other` sequences.
  /// - Parameters:
  ///   - base: the ``AsyncSequence`` that drives the production of the output tuples
  ///   - other1: the first ``AsyncSequence`` from which the latest known element is gathered to form the output tuple
  ///   - other2: the second ``AsyncSequence`` from which the latest known element is gathered to form the output tuple
  public init(_ base: Base, _ other1: Other1, _ other2: Other2) {
    self.base = base
    self.other1 = AsyncCurrentElementSequence(other1)
    self.other2 = AsyncCurrentElementSequence(other2)
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      self.base.makeAsyncIterator(),
      self.other1.makeAsyncIterator(),
      self.other2.makeAsyncIterator()
    )
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    var base: Base.AsyncIterator
    var other1: AsyncCurrentElementSequence<Other1>.AsyncIterator
    var other2: AsyncCurrentElementSequence<Other2>.AsyncIterator
    var isFinished = false

    init(
      _ base: Base.AsyncIterator,
      _ other1: AsyncCurrentElementSequence<Other1>.AsyncIterator,
      _ other2: AsyncCurrentElementSequence<Other2>.AsyncIterator
    ) {
      self.base = base
      self.other1 = other1
      self.other2 = other2
    }

    public mutating func next() async rethrows -> Element? {
      guard !self.isFinished else { return nil }

      var baseElement: Base.Element?
      var lastKnownOther1State: AsyncCurrentElementSequence<Other1>.State?
      var lastKnownOther2State: AsyncCurrentElementSequence<Other2>.State?

      var hasElementFromOther1 = false
      var hasOther1Finished = false

      var hasElementFromOther2 = false
      var hasOther2Finished = false

      repeat {
        guard !Task.isCancelled else {
          self.other1.task.cancel()
          self.other2.task.cancel()
          return nil
        }

        do {
          baseElement = try await self.base.next()
        } catch {
          self.other1.task.cancel()
          self.other2.task.cancel()
          throw error
        }

        lastKnownOther1State = await self.other1.next()
        lastKnownOther2State = await self.other2.next()

        switch lastKnownOther1State {
        case .none: hasOther1Finished = true
        case .some(.noElement): hasElementFromOther1 = false
        case .some(.element): hasElementFromOther1 = true
        case .some(.finished): break
        }

        switch lastKnownOther2State {
        case .none: hasOther2Finished = true
        case .some(.noElement): hasElementFromOther2 = false
        case .some(.element): hasElementFromOther2 = true
        case .some(.finished): break
        }
      } while (!hasElementFromOther1 && !hasOther1Finished) || (!hasElementFromOther2 && !hasOther2Finished)

      guard let nonNilOther1State = lastKnownOther1State, case let .element(other1Result) = nonNilOther1State else {
        self.isFinished = true
        return nil
      }

      guard let nonNilOther2State = lastKnownOther2State, case let .element(other2Result) = nonNilOther2State else {
        self.isFinished = true
        return nil
      }

      guard let nonNilBaseElement = baseElement else {
        self.other1.task.cancel()
        self.other2.task.cancel()
        self.isFinished = true
        return nil
      }

      return (nonNilBaseElement, try other1Result._rethrowGet(), try other2Result._rethrowGet())
    }
  }
}

struct AsyncCurrentElementSequence<Base: AsyncSequence>: AsyncSequence where Base: Sendable {
  typealias Element = State
  typealias AsyncIterator = Iterator

  enum State {
    case noElement
    case element(Result<Base.Element, any Error>)
    case finished
  }

  let base: Base

  init(_ base: Base) {
    self.base = base
  }

  func makeAsyncIterator() -> Iterator {
    Iterator(self.base)
  }

  struct Iterator: AsyncIteratorProtocol {
    let state = ManagedCriticalState<State>(.noElement)
    let task: Task<Void, Never>

    init(_ base: Base) {
      let localState = self.state
      self.task = Task {
        do {
          for try await element in base {
            localState.withCriticalRegion { state in
              switch state {
              case .noElement, .element:
                state = .element(.success(element))
              case .finished:
                state = .finished
              }
            }
          }
          
          localState.withCriticalRegion { state in
            state = .finished
          }
        } catch {
          localState.withCriticalRegion { state in
            state = .element(.failure(error))
          }
        }
      }
    }

    func next() async -> Element? {
      guard !Task.isCancelled else { return nil }

      let state = self.state.withCriticalRegion { state in
        state
      }

      if case .finished = state {
        return nil
      }

      return state
    }
  }
}

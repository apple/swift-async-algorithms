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
  /// let sequence = base.withLatest(from: other)
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
  /// - Returns: an ``AsyncWithLatestFromSequence`` where elements are a tuple of an element from `self` and the
  /// latest known element (if any) from the `other` sequence.
  func withLatest<Other: AsyncSequence>(
    from other: Other
  ) -> AsyncWithLatestFromSequence<Self, Other> {
    AsyncWithLatestFromSequence(self, other)
  }
}

/// ``AsyncWithLatestFromSequence`` is an ``AsyncSequence`` where elements are a tuple of an element from `base` and the
/// latest known element (if any) from the `other` sequence.
public struct AsyncWithLatestFromSequence<Base: AsyncSequence, Other: AsyncSequence>: AsyncSequence
where Other: Sendable, Other.Element: Sendable {
  public typealias Element = (Base.Element, Other.Element)
  public typealias AsyncIterator = Iterator

  let base: Base
  let other: Other

  // for testability purpose
  var onBaseElement: (@Sendable (Base.Element) -> Void)?
  var onOtherElement: (@Sendable (Other.Element?) -> Void)?

  init(_ base: Base, _ other: Other) {
    self.base = base
    self.other = other
  }

  public func makeAsyncIterator() -> Iterator {
    var iterator = Iterator(
      base: self.base.makeAsyncIterator(),
      other: self.other
    )
    iterator.onBaseElement = onBaseElement
    iterator.onOtherElement = onOtherElement
    iterator.startOther()
    return iterator
  }

  public struct Iterator: AsyncIteratorProtocol {
    enum OtherState {
      case idle
      case element(Result<Other.Element, Error>)
    }

    enum BaseDecision {
      case pass
      case returnElement(Result<Element, Error>)
    }

    var base: Base.AsyncIterator
    let other: Other
    let otherState: ManagedCriticalState<OtherState>
    var otherTask: Task<Void, Never>?
    var isTerminated: Bool

    // for testability purpose
    var onBaseElement: (@Sendable (Base.Element) -> Void)?
    var onOtherElement: (@Sendable (Other.Element?) -> Void)?

    public init(base: Base.AsyncIterator, other: Other) {
      self.base = base
      self.other = other
      self.otherState = ManagedCriticalState(.idle)
      self.isTerminated = false
    }

    mutating func startOther() {
      self.otherTask = Task { [other, otherState, onOtherElement] in
        do {
          for try await element in other {
            otherState.withCriticalRegion { state in
              state = .element(.success(element))
            }
            onOtherElement?(element)
          }
        } catch {
          otherState.withCriticalRegion { state in
            state = .element(.failure(error))
          }
        }
      }
    }

    public mutating func next() async rethrows -> Element? {
      guard !self.isTerminated else { return nil }

      return try await withTaskCancellationHandler { [otherTask] in
        otherTask?.cancel()
      } operation: { [otherTask, otherState, onBaseElement] in
        do {
          while true {
            guard let baseElement = try await self.base.next() else {
              self.isTerminated = true
              otherTask?.cancel()
              return nil
            }

            onBaseElement?(baseElement)

            let decision = otherState.withCriticalRegion { state -> BaseDecision in
              switch state {
                case .idle:
                  return .pass
                case .element(.success(let otherElement)):
                  return .returnElement(.success((baseElement, otherElement)))
                case .element(.failure(let otherError)):
                  return .returnElement(.failure(otherError))
              }
            }

            switch decision {
              case .pass:
                continue
              case .returnElement(let result):
                return try result._rethrowGet()
            }
          }
        } catch {
          self.isTerminated = true
          otherTask?.cancel()
          throw error
        }
      }
    }
  }
}

extension AsyncWithLatestFromSequence: Sendable where Base: Sendable {}

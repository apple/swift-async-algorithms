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
  /// let sequence = base.withLatest(from: other1, other2)
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
  /// - Returns: an ``AsyncWithLatestFrom2Sequence`` where elements are a tuple of an element from `self` and the
  /// latest known elements (if any) from the `other` sequences.
  func withLatest<Other1: AsyncSequence, Other2: AsyncSequence>(
    from other1: Other1,
    _ other2: Other2
  ) -> AsyncWithLatestFrom2Sequence<Self, Other1, Other2> {
    AsyncWithLatestFrom2Sequence(self, other1, other2)
  }
}

/// ``AsyncWithLatestFrom2Sequence`` is an ``AsyncSequence`` where elements are a tuple of an element from `base` and the
/// latest known element (if any) from the `other` sequences.
public struct AsyncWithLatestFrom2Sequence<Base: AsyncSequence, Other1: AsyncSequence, Other2: AsyncSequence>: AsyncSequence
where Other1: Sendable, Other2: Sendable, Other1.Element: Sendable, Other2.Element: Sendable {
  public typealias Element = (Base.Element, Other1.Element, Other2.Element)
  public typealias AsyncIterator = Iterator

  let base: Base
  let other1: Other1
  let other2: Other2

  // for testability purpose
  var onBaseElement: (@Sendable (Base.Element) -> Void)?
  var onOther1Element: (@Sendable (Other1.Element?) -> Void)?
  var onOther2Element: (@Sendable (Other2.Element?) -> Void)?

  init(_ base: Base, _ other1: Other1, _ other2: Other2) {
    self.base = base
    self.other1 = other1
    self.other2 = other2
  }

  public func makeAsyncIterator() -> Iterator {
    var iterator = Iterator(
      base: self.base.makeAsyncIterator(),
      other1: self.other1,
      other2: self.other2
    )
    iterator.onBaseElement = onBaseElement
    iterator.onOther1Element = onOther1Element
    iterator.onOther2Element = onOther2Element
    iterator.startOthers()
    return iterator
  }

  public struct Iterator: AsyncIteratorProtocol {
    enum Other1State {
      case idle
      case element(Result<Other1.Element, Error>)
    }

    enum Other2State {
      case idle
      case element(Result<Other2.Element, Error>)
    }

    struct OthersState {
      var other1State: Other1State
      var other2State: Other2State

      static var idle: OthersState {
        OthersState(other1State: .idle, other2State: .idle)
      }
    }

    enum BaseDecision {
      case pass
      case returnElement(Result<Element, Error>)
    }

    var base: Base.AsyncIterator
    let other1: Other1
    let other2: Other2

    let othersState: ManagedCriticalState<OthersState>
    var othersTask: Task<Void, Never>?

    var isTerminated: ManagedCriticalState<Bool>

    // for testability purpose
    var onBaseElement: (@Sendable (Base.Element) -> Void)?
    var onOther1Element: (@Sendable (Other1.Element?) -> Void)?
    var onOther2Element: (@Sendable (Other2.Element?) -> Void)?

    public init(base: Base.AsyncIterator, other1: Other1, other2: Other2) {
      self.base = base
      self.other1 = other1
      self.other2 = other2
      self.othersState = ManagedCriticalState(.idle)
      self.isTerminated = ManagedCriticalState(false)
    }

    mutating func startOthers() {
      self.othersTask = Task { [othersState, other1, other2, onOther1Element, onOther2Element] in
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            do {
              for try await element in other1 {
                othersState.withCriticalRegion { state in
                  state.other1State = .element(.success(element))
                }
                onOther1Element?(element)
              }
            } catch {
              othersState.withCriticalRegion { state in
                state.other1State = .element(.failure(error))
              }
            }
          }

          group.addTask {
            do {
              for try await element in other2 {
                othersState.withCriticalRegion { state in
                  state.other2State = .element(.success(element))
                }
                onOther2Element?(element)
              }
            } catch {
              othersState.withCriticalRegion { state in
                state.other2State = .element(.failure(error))
              }
            }
          }
        }
      }
    }

    public mutating func next() async rethrows -> Element? {
      let shouldReturnNil = self.isTerminated.withCriticalRegion { $0 }
      guard !shouldReturnNil else { return nil }

      return try await withTaskCancellationHandler { [isTerminated, othersTask] in
        isTerminated.withCriticalRegion { isTerminated in
          isTerminated = true
        }
        othersTask?.cancel()
      } operation: { [othersTask, othersState, onBaseElement] in
        do {
          while true {
            guard let baseElement = try await self.base.next() else {
              isTerminated.withCriticalRegion { isTerminated in
                isTerminated = true
              }
              othersTask?.cancel()
              return nil
            }

            onBaseElement?(baseElement)

            let decision = othersState.withCriticalRegion { state -> BaseDecision in
              switch (state.other1State, state.other2State) {
                case (.idle, _):
                  return .pass
                case (_, .idle):
                  return .pass
                case (.element(.success(let other1Element)), .element(.success(let other2Element))):
                  return .returnElement(.success((baseElement, other1Element, other2Element)))
                case (.element(.failure(let otherError)), _):
                  return .returnElement(.failure(otherError))
                case (_, .element(.failure(let otherError))):
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
          isTerminated.withCriticalRegion { isTerminated in
            isTerminated = true
          }
          othersTask?.cancel()
          throw error
        }
      }
    }
  }
}

extension AsyncWithLatestFrom2Sequence: Sendable where Base: Sendable { }

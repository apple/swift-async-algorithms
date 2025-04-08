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
extension AsyncSequenceValidationDiagram {
  public struct Specification: Sendable {
    public let specification: String
    public let location: SourceLocation

    init(specification: String, location: SourceLocation) {
      self.specification = specification
      self.location = location
    }
  }

  public struct Input: AsyncSequence, Sendable {
    public typealias Element = String

    struct State {
      var emissions = [(Clock.Instant, Event)]()
    }

    let state = ManagedCriticalState(State())
    let queue: WorkQueue
    let index: Int

    public struct Iterator: AsyncIteratorProtocol, Sendable {
      let state: ManagedCriticalState<State>
      let queue: WorkQueue
      let index: Int
      var active: (Clock.Instant, [Result<String?, Error>])?
      var eventIndex = 0

      mutating func apply(when: Clock.Instant, results: [Result<String?, Error>]) async throws -> Element? {
        let token = queue.prepare()
        if eventIndex + 1 >= results.count {
          active = nil
        }
        defer {
          if active != nil {
            eventIndex += 1
          } else {
            eventIndex = 0
          }
        }
        return try await withTaskCancellationHandler {
          try await withUnsafeThrowingContinuation { continuation in
            queue.enqueue(
              Context.currentJob,
              deadline: when,
              continuation: continuation,
              results[eventIndex],
              index: index,
              token: token
            )
          }
        } onCancel: { [queue] in
          queue.cancel(token)
        }
      }

      public mutating func next() async throws -> Element? {
        guard let (when, results) = active else {
          let next = state.withCriticalRegion { state -> (Clock.Instant, Event)? in
            guard state.emissions.count > 0 else {
              return nil
            }
            return state.emissions.removeFirst()
          }
          guard let next = next else {
            return nil
          }
          let when = next.0
          let results = next.1.results
          active = (when, results)
          return try await apply(when: when, results: results)
        }
        return try await apply(when: when, results: results)
      }
    }

    public func makeAsyncIterator() -> Iterator {
      Iterator(state: state, queue: queue, index: index)
    }

    func parse<Theme: AsyncSequenceValidationTheme>(_ dsl: String, theme: Theme, location: SourceLocation) throws {
      let emissions = try Event.parse(dsl, theme: theme, location: location)
      state.withCriticalRegion { state in
        state.emissions = emissions
      }
    }

    var end: Clock.Instant? {
      return state.withCriticalRegion { state in
        state.emissions.map { $0.0 }.sorted().last
      }
    }
  }

  public struct InputList: RandomAccessCollection, Sendable {
    let state = ManagedCriticalState([Input]())
    let queue: WorkQueue

    public var startIndex: Int { return 0 }
    public var endIndex: Int {
      state.withCriticalRegion { $0.count }
    }

    public subscript(position: Int) -> AsyncSequenceValidationDiagram.Input {
      get {
        return state.withCriticalRegion { state in
          if position >= state.count {
            for _ in state.count...position {
              state.append(Input(queue: queue, index: position))
            }
          }
          return state[position]
        }
      }
    }
  }
}

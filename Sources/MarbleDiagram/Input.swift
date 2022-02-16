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

extension MarbleDiagram {
  public struct Input: AsyncSequence, Sendable {
    public typealias Element = String
    
    struct State {
      var emissions = [(Clock.Instant, Event)]()
    }
    
    let state = ManagedCriticalState(State())
    let clock: Clock
    
    public struct Iterator: AsyncIteratorProtocol {
      let state: ManagedCriticalState<State>
      let clock: Clock
      
      public mutating func next() async throws -> Element? {
        let next = state.withCriticalRegion { state -> (Clock.Instant, Event)? in
          guard state.emissions.count > 0 else {
            return nil
          }
          return state.emissions.removeFirst()
        }
        guard let next = next else {
          return nil
        }
        try? await clock.sleep(until: next.0)
        return try next.1.result.get()
      }
    }
    
    public func makeAsyncIterator() -> Iterator {
      Iterator(state: state, clock: clock)
    }
    
    func parse<Theme: MarbleDiagramTheme>(_ dsl: String, theme: Theme) {
      let emissions = Event.parse(dsl, theme: theme)
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
    let clock: Clock
    
    public var startIndex: Int { return 0 }
    public var endIndex: Int {
      state.withCriticalRegion { $0.count }
    }
    
    public subscript(position: Int) -> MarbleDiagram.Input {
      get {
        return state.withCriticalRegion { state in
          if position >= state.count {
            for _ in state.count...position {
              state.append(Input(clock: clock))
            }
          }
          return state[position]
        }
      }
    }
  }
}

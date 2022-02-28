//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension AsyncSequence {

  public func chunked<Signal, Collected: RangeReplaceableCollection>(byCount count: Int, andSignal signal: Signal, collectedInto: Collected.Type) -> AsyncChunksOfCountAndSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountAndSignalSequence(self, count: count, signal: signal)
  }

  public func chunked<Signal>(byCount count: Int, andSignal signal: Signal) -> AsyncChunksOfCountAndSignalSequence<Self, [Element], Signal> {
    chunked(byCount: count, andSignal: signal, collectedInto: [Element].self)
  }

  public func chunked<Signal, Collected: RangeReplaceableCollection>(bySignal signal: Signal, collectedInto: Collected.Type) -> AsyncChunksOfCountAndSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountAndSignalSequence(self, count: nil, signal: signal)
  }

  public func chunked<Signal>(bySignal signal: Signal) -> AsyncChunksOfCountAndSignalSequence<Self, [Element], Signal> {
    chunked(bySignal: signal, collectedInto: [Element].self)
  }

  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(byCount count: Int, andTime timer: AsyncTimerSequence<C>, collectedInto: Collected.Type) -> AsyncChunksOfCountAndSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountAndSignalSequence(self, count: count, signal: timer)
  }

  public func chunked<C: Clock>(byCount count: Int, andTime timer: AsyncTimerSequence<C>) -> AsyncChunksOfCountAndSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
    chunked(byCount: count, andTime: timer, collectedInto: [Element].self)
  }

  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(byTime timer: AsyncTimerSequence<C>, collectedInto: Collected.Type) -> AsyncChunksOfCountAndSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountAndSignalSequence(self, count: nil, signal: timer)
  }

  public func chunked<C: Clock>(byTime timer: AsyncTimerSequence<C>) -> AsyncChunksOfCountAndSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
    chunked(byTime: timer, collectedInto: [Element].self)
  }

}

public struct AsyncChunksOfCountAndSignalSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection, Signal: AsyncSequence>: AsyncSequence, Sendable where Collected.Element == Base.Element, Base: Sendable, Signal: Sendable, Base.AsyncIterator: Sendable, Signal.AsyncIterator: Sendable, Base.Element: Sendable, Signal.Element: Sendable {

  public typealias Element = Collected

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    enum Partial: Sendable {
      case base(Result<Base.Element?, Error>, Base.AsyncIterator)
      case signal(Result<Signal.Element?, Error>, Signal.AsyncIterator)
    }
    
    let count: Int?
    
    var state: (PartialIteration<Base.AsyncIterator, Partial>, PartialIteration<Signal.AsyncIterator, Partial>)
    
    init(base: Base.AsyncIterator, count: Int?, signal: Signal.AsyncIterator) {
      self.count = count
      self.state = (.idle(base), .idle(signal))
    }
    
    public mutating func next() async rethrows -> Collected? {
      var collected: Collected?
      while true  {
        if Task.isCancelled {
          state.0.cancel()
          state.1.cancel()
          return nil
        }
        switch state {
        case (.terminal, _): fallthrough
        case (_, .terminal):
          return nil
        default:
          let baseTask = state.0.task {
            .base($0, $1)
          }
          let signalTask = state.1.task {
            .signal($0, $1)
          }
          switch await Task.select([baseTask, signalTask].compactMap({ $0 })).value {
          case .base(let result, let iterator):
            do {
              state.0 = .idle(iterator)
              guard let element = try result.get() else {
                signalTask?.cancel()
                state = (.terminal, .terminal)
                return collected
              }
              if collected == nil {
                collected = Collected()
              }
              collected?.append(element)
              if collected?.count == count {
                return collected
              }
            } catch {
              signalTask?.cancel()
              state = (.terminal, .terminal)
              try result._rethrowError()
            }
            if collected == nil {
              collected = Collected()
            }
            
          case .signal(let result, let iterator):
            state.1 = .idle(iterator)
            switch result {
            case .success(let signal):
              if signal != nil {
                if collected != nil {
                  return collected
                }
              } else {
                baseTask?.cancel()
                state = (.terminal, .terminal)
                return collected
              }
            case .failure:
              baseTask?.cancel()
              state = (.terminal, .terminal)
              try result._rethrowError()
            }
          }
        }
      }
    }
  }

  let base: Base
  let signal: Signal
  let count: Int?
  init(_ base: Base, count: Int?, signal: Signal) {
    if let count = count {
      precondition(count > 0)
    }

    self.base = base
    self.count = count
    self.signal = signal
  }

  public func makeAsyncIterator() -> Iterator {
    return Iterator(base: base.makeAsyncIterator(), count: count, signal: signal.makeAsyncIterator())
  }
}

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
    let count: Int?
    var state: (PartialIterationState<Base.AsyncIterator, Partial2<Base.AsyncIterator, Signal.AsyncIterator>>, PartialIterationState<Signal.AsyncIterator, Partial2<Base.AsyncIterator, Signal.AsyncIterator>>)
    
    init(base: Base.AsyncIterator, count: Int?, signal: Signal.AsyncIterator) {
      self.count = count
      self.state = (.idle(base), .idle(signal))
    }
    
    public mutating func next() async rethrows -> Collected? {
      if Task.isCancelled {
        state.0.cancel()
        state.1.cancel()
        return nil
      }
      switch state {
      case (.idle, .terminal):
        state.0.cancel()
        return nil
      case (.terminal, .idle):
        state.1.cancel()
        return nil
      case (.terminal, .terminal):
        return nil
      default:
        var collected: Collected?
        while true {
          let tasks = [
            state.0.task(),
            state.1.task()
          ]
          switch await Task.select(tasks.compactMap({ $0 })).value {
          case .first(let result, let iterator):
            do {
              guard let element = try state.0.resolve(result, iterator) else {
                state.1.cancel()
                return collected
              }
              if collected == nil {
                collected = Collected()
              }
              collected!.append(element)
              if collected?.count == count {
                return collected
              }
            } catch {
              state.1.cancel()
              throw error
            }
          case .second(let result, let iterator):
            do {
              guard try state.1.resolve(result, iterator) != nil else {
                state.0.cancel()
                return collected
              }
              if collected != nil {
                return collected
              }
            } catch {
              state.0.cancel()
              throw error
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

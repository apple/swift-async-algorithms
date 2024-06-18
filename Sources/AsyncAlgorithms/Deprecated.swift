

extension AsyncSequence {
  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type of a given count or when a signal `AsyncSequence` produces an element.
  @_disfavoredOverload
  @available(*, deprecated, renamed: "chunks(ofCount:or:into:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunks<Signal, Collected: RangeReplaceableCollection>(ofCount count: Int, or signal: Signal, into: Collected.Type) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: count, signal: signal, produceEmptyChunks: false)
  }

  /// Creates an asynchronous sequence that creates chunks of a given count or when a signal `AsyncSequence` produces an element.
  @_disfavoredOverload
  @available(*, deprecated, renamed: "chunks(ofCount:or:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunks<Signal>(ofCount count: Int, or signal: Signal) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal> {
    chunks(ofCount: count, or: signal, into: [Element].self)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type when a signal `AsyncSequence` produces an element.
  @_disfavoredOverload
  @available(*, deprecated, renamed: "chunked(by:into:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunked<Signal, Collected: RangeReplaceableCollection>(by signal: Signal, into: Collected.Type) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: nil, signal: signal, produceEmptyChunks: false)
  }

  /// Creates an asynchronous sequence that creates chunks when a signal `AsyncSequence` produces an element.
  @_disfavoredOverload
  @available(*, deprecated, renamed: "chunked(by:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunked<Signal>(by signal: Signal) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal> {
    chunked(by: signal, into: [Element].self)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type of a given count or when an `AsyncTimerSequence` fires.
  @_disfavoredOverload
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  @available(*, deprecated, renamed: "chunks(ofCount:or:into:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunks<C: Clock, Collected: RangeReplaceableCollection>(ofCount count: Int, or timer: AsyncTimerSequence<C>, into: Collected.Type) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: count, signal: timer, produceEmptyChunks: false)
  }

  /// Creates an asynchronous sequence that creates chunks of a given count or when an `AsyncTimerSequence` fires.
  @_disfavoredOverload
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  @available(*, deprecated, renamed: "chunks(ofCount:or:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunks<C: Clock>(ofCount count: Int, or timer: AsyncTimerSequence<C>) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
    chunks(ofCount: count, or: timer, into: [Element].self)
  }

  /// Creates an asynchronous sequence that creates chunks of a given `RangeReplaceableCollection` type when an `AsyncTimerSequence` fires.
  @_disfavoredOverload
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  @available(*, deprecated, renamed: "chunked(by:into:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(by timer: AsyncTimerSequence<C>, into: Collected.Type) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> where Collected.Element == Element {
    AsyncChunksOfCountOrSignalSequence(self, count: nil, signal: timer, produceEmptyChunks: false)
  }

  /// Creates an asynchronous sequence that creates chunks when an `AsyncTimerSequence` fires.
  @_disfavoredOverload
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  @available(*, deprecated, renamed: "chunked(by:produceEmptyChunks:)", message: "This method has been deprecated to allow the option for sequences to produce empty chunks.")
  public func chunked<C: Clock>(by timer: AsyncTimerSequence<C>) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>> {
    chunked(by: timer, into: [Element].self)
  }
}

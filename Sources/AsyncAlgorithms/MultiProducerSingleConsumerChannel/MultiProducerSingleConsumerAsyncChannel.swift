//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.1)
/// An error that is thrown from the various `send` methods of the
/// ``MultiProducerSingleConsumerAsyncChannel/Source``.
///
/// This error is thrown when the channel is already finished when
/// trying to send new elements to the source.
@available(AsyncAlgorithms 1.1, *)
public struct MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError: Error {
  @usableFromInline
  init() {}
}

/// A multi-producer single-consumer channel.
///
/// The ``MultiProducerSingleConsumerAsyncChannel`` provides a ``MultiProducerSingleConsumerAsyncChannel/Source`` to
/// send values to the channel. The channel supports different back pressure strategies to control the
/// buffering and demand. The channel will buffer values until its backpressure strategy decides that the
/// producer have to wait.
///
/// This channel is also suitable for the single-producer single-consumer use-case
///
/// ## Using a MultiProducerSingleConsumerAsyncChannel
///
/// To use a ``MultiProducerSingleConsumerAsyncChannel`` you have to create a new channel with its source first by calling
/// the ``MultiProducerSingleConsumerAsyncChannel/makeChannel(of:throwing:backpressureStrategy:)`` method.
/// Afterwards, you can pass the source to the producer and the channel to the consumer.
///
/// ```
/// let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
///     of: Int.self,
///     backpressureStrategy: .watermark(low: 2, high: 4)
/// )
///
/// // The channel and source can be extracted from the returned type
/// let channel = consume channelAndSource.channel
/// let source = consume channelAndSource.source
/// ```
///
/// ### Asynchronous producing
///
/// Values can be send to the source from asynchronous contexts using ``MultiProducerSingleConsumerAsyncChannel/Source/send(contentsOf:)-1h7t9``
/// and ``MultiProducerSingleConsumerAsyncChannel/Source/send(_:)->()``. Backpressure results in calls
/// to the `send` methods to be suspended. Once more elements should be produced the `send` methods will be resumed.
///
/// ```
/// try await withThrowingTaskGroup(of: Void.self) { group in
///     group.addTask {
///         try await source.send(1)
///         try await source.send(2)
///         try await source.send(3)
///     }
///
///     for await element in channel {
///         print(element)
///     }
/// }
/// ```
///
/// ### Synchronous produceing
///
/// Values can also be send to the source from synchronous context. Backpressure is also exposed on the synchronous contexts; however,
/// it is up to the caller to decide how to properly translate the backpressure to underlying producer e.g. by blocking the thread.
///
/// ```swift
/// do {
///     let sendResult = try source.send(contentsOf: sequence)
///
///     switch sendResult {
///     case .produceMore:
///        // Trigger more production in the underlying system
///
///     case .enqueueCallback(let callbackHandle):
///         // There are enough values in the channel already. We need to enqueue
///         // a callback to get notified when we should produce more.
///         callbackHandle.enqueueCallback(onProduceMore: { result in
///             switch result {
///             case .success:
///                 // Trigger more production in the underlying system
///             case .failure(let error):
///                 // Terminate the underlying producer
///             }
///         })
///     }
/// } catch {
///     // `send(contentsOf:)` throws if the channel already terminated
/// }
/// ```
///
/// ### Multiple producers
///
/// To support multiple producers the source offers a ``Source/makeAdditionalSource()`` method to produce a new source.
///
/// ### Terminating the production of values
///
/// The consumer can be terminated through multiple ways:
/// - Calling ``Source/finish(throwing:)``.
/// - Deiniting all sources.
///
/// In both cases, if there are still elements buffered by the channel, then the consumer will receive
/// all buffered elements. Afterwards it will be terminated.
///
/// ### Observing termination of the consumer
///
/// When the consumer stops consumption by either deiniting the channel or the task calling ``next(isolation:)``
/// getting cancelled, the source will get notified about the termination if a termination callback has been set
/// before by calling ``Source/setOnTerminationCallback(_:)``.
@available(AsyncAlgorithms 1.1, *)
public struct MultiProducerSingleConsumerAsyncChannel<Element, Failure: Error>: ~Copyable {
  /// The backing storage.
  @usableFromInline
  let storage: _Storage

  /// A struct containing the initialized channel and source.
  ///
  /// This struct can be deconstructed by consuming the individual
  /// components from it.
  ///
  /// ```swift
  /// let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
  ///     of: Int.self,
  ///     backpressureStrategy: .watermark(low: 5, high: 10)
  /// )
  /// var channel = consume channelAndSource.channel
  /// var source = consume channelAndSource.source
  /// ```
  @frozen
  public struct ChannelAndStream: ~Copyable {
    /// The channel.
    @usableFromInline
    var channel: MultiProducerSingleConsumerAsyncChannel?

    /// Takes and returns the channel.
    ///
    /// - Important: If this is called more than once it will result in a runtime crash.
    @inlinable
    public mutating func takeChannel() -> sending MultiProducerSingleConsumerAsyncChannel {
      return self.channel.takeSending()!
    }
    /// The source.
    public var source: Source

    init(
      channel: consuming MultiProducerSingleConsumerAsyncChannel,
      source: consuming Source
    ) {
      self.channel = .some(channel)
      self.source = source
    }
  }

  /// Initializes a new ``MultiProducerSingleConsumerAsyncChannel`` and an ``MultiProducerSingleConsumerAsyncChannel/Source``.
  ///
  /// - Parameters:
  ///   - elementType: The element type of the channel.
  ///   - failureType: The failure type of the channel.
  ///   - backpressureStrategy: The backpressure strategy that the channel should use.
  /// - Returns: A struct containing the channel and its source. The source should be passed to the
  ///   producer while the channel should be passed to the consumer.
  public static func makeChannel(
    of elementType: Element.Type = Element.self,
    throwing failureType: Failure.Type = Never.self,
    backpressureStrategy: Source.BackpressureStrategy
  ) -> sending ChannelAndStream {
    let storage = _Storage(
      backpressureStrategy: backpressureStrategy.internalBackpressureStrategy
    )
    let source = Source(storage: storage)

    return .init(channel: .init(storage: storage), source: source)
  }

  init(storage: _Storage) {
    self.storage = storage
  }

  deinit {
    self.storage.channelDeinitialized()
  }

  /// Returns the next element.
  ///
  /// If this method returns `nil` it indicates that no further values can ever
  /// be returned. The channel automatically closes when all sources have been deinited.
  ///
  /// If there are no elements and the channel has not been finished yet, this method will
  /// suspend until an element is send to the channel.
  ///
  /// If the task calling this method is cancelled this method will return `nil`.
  ///
  /// - Parameter isolation: The callers isolation.
  /// - Returns: The next buffered element.
  @inlinable
  public mutating func next(
    isolation: isolated (any Actor)? = #isolation
  ) async throws(Failure) -> Element? {
    do {
      return try await self.storage.next()
    } catch {
      // This force-cast is safe since we only allow closing the source with this failure
      // We only need this force cast since continuations don't support typed throws yet.
      throw error as! Failure
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
extension MultiProducerSingleConsumerAsyncChannel {
  /// A struct to send values to the channel.
  ///
  /// Use this source to provide elements to the channel by calling one of the `send` methods.
  public struct Source: ~Copyable {
    /// A struct representing the backpressure of the channel.
    public struct BackpressureStrategy: Sendable {
      var internalBackpressureStrategy: _InternalBackpressureStrategy

      /// A backpressure strategy using a high and low watermark to suspend and resume production respectively.
      ///
      /// - Parameters:
      ///   - low: When the number of buffered elements drops below the low watermark, producers will be resumed.
      ///   - high: When the number of buffered elements rises above the high watermark, producers will be suspended.
      public static func watermark(low: Int, high: Int) -> BackpressureStrategy {
        .init(
          internalBackpressureStrategy: .watermark(
            .init(low: low, high: high, waterLevelForElement: nil)
          )
        )
      }

      /// A backpressure strategy using a high and low watermark to suspend and resume production respectively.
      ///
      /// - Parameters:
      ///   - low: When the number of buffered elements drops below the low watermark, producers will be resumed.
      ///   - high: When the number of buffered elements rises above the high watermark, producers will be suspended.
      ///   - waterLevelForElement: A closure used to compute the contribution of each buffered element to the current water level.
      ///
      /// - Important: `waterLevelForElement` will be called during a lock on each element when it is written into the source and when
      /// it is consumed from the channel, so it must be side-effect free and at best constant in time.
      public static func watermark(
        low: Int,
        high: Int,
        waterLevelForElement: @escaping @Sendable (borrowing Element) -> Int
      ) -> BackpressureStrategy {
        .init(
          internalBackpressureStrategy: .watermark(
            .init(low: low, high: high, waterLevelForElement: waterLevelForElement)
          )
        )
      }
    }

    /// A type that indicates the result of sending elements to the source.
    public enum SendResult: ~Copyable, Sendable {
      /// A handle that is returned when the channel's backpressure strategy indicated that production should
      /// be suspended. Use this handle to enqueue a callback by  calling the ``CallbackHandle/enqueueCallback(onProduceMore:)`` method.
      ///
      /// - Important: ``CallbackHandle/enqueueCallback(onProduceMore:)`` and ``CallbackHandle/cancelCallback()`` must
      /// only be called once.
      public struct CallbackHandle: Sendable, Hashable {
        @usableFromInline
        let _id: UInt64

        @usableFromInline
        let _storage: _Storage

        @usableFromInline
        init(id: UInt64, storage: _Storage) {
          self._id = id
          self._storage = storage
        }

        /// Enqueues a callback that will be invoked once more elements should be produced.
        ///
        /// - Important: Calling enqueue more than once is **not allowed**.
        ///
        /// - Parameters:
        ///   - onProduceMore: The callback which gets invoked once more elements should be produced.
        @inlinable
        public mutating func enqueueCallback(
          onProduceMore: sending @escaping (Result<Void, Error>) -> Void
        ) {
          self._storage.enqueueProducer(callbackToken: self._id, onProduceMore: onProduceMore)
        }

        /// Cancel an enqueued callback.
        ///
        /// - Note: This methods supports being called before ``enqueueCallback(onProduceMore:)`` is called.
        ///
        /// - Important: Calling enqueue more than once is **not allowed**.
        @inlinable
        public mutating func cancelCallback() {
          self._storage.cancelProducer(callbackToken: self._id)
        }

        @inlinable
        public static func == (lhs: Self, rhs: Self) -> Bool {
          lhs._id == rhs._id
        }

        @inlinable
        public func hash(into hasher: inout Hasher) {
          hasher.combine(self._id)
        }
      }

      /// Indicates that more elements should be produced and send to the source.
      case produceMore

      /// Indicates that a callback should be enqueued.
      case enqueueCallback(CallbackHandle)
    }

    @usableFromInline
    let _storage: _Storage

    @usableFromInline
    let _id: UInt64

    internal init(
      storage: _Storage
    ) {
      self._storage = storage
      self._id = self._storage.sourceInitialized()
    }

    deinit {
      self._storage.sourceDeinitialized()
    }

    /// Sets a callback to invoke when the channel terminated.
    ///
    /// This is called after the last element has been consumed by the channel.
    /// If the channel has already terminated this callback is called immediately.
    ///
    /// - Important: Only one termination callback can be set per source. Setting a callback if
    /// a previous one has been set will override the previous one.
    public func setOnTerminationCallback(_ callback: (@Sendable () -> Void)?) {
      self._storage.setOnTerminationCallback(sourceID: self._id, callback: callback)
    }

    /// Creates a new source which can be used to send elements to the channel concurrently.
    ///
    /// The channel will only automatically be finished if all existing sources have been deinited.
    ///
    /// - Returns: A new source for sending elements to the channel.
    public mutating func makeAdditionalSource() -> sending Self {
      .init(storage: self._storage)
    }

    /// Sends new elements to the channel.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// first element of the provided sequence. If the channel already terminated then this method will throw an error
    /// indicating the failure.
    ///
    /// - Parameter sequence: The elements to send to the channel.
    /// - Returns: The result that indicates if more elements should be produced at this time.
    @inlinable
    public mutating func send<S>(
      contentsOf sequence: consuming sending S
    ) throws -> SendResult where Element == S.Element, S: Sequence, Element: Copyable {
      try self._storage.send(contentsOf: sequence)
    }

    /// Send the element to the channel.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// provided element. If the channel already terminated then this method will throw an error
    /// indicating the failure.
    ///
    /// - Parameter element: The element to send to the channel.
    /// - Returns: The result that indicates if more elements should be produced at this time.
    @inlinable
    public mutating func send(_ element: consuming sending Element) throws -> SendResult {
      try self._storage.send(contentsOf: CollectionOfOne(element))
    }

    /// Send new elements to the channel and provide a callback which will be invoked once more elements should be produced.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// first element of the provided sequence. If the channel already terminated then `onProduceMore` will be invoked with
    /// a `Result.failure`.
    ///
    /// - Parameters:
    ///   - sequence: The elements to send to the channel.
    ///   - onProduceMore: The callback which gets invoked once more elements should be produced. This callback might be
    ///   invoked during the call to ``send(contentsOf:onProduceMore:)``.
    @inlinable
    public mutating func send<S>(
      contentsOf sequence: consuming sending S,
      onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void
    ) where Element == S.Element, S: Sequence, Element: Copyable {
      do {
        let sendResult = try self.send(contentsOf: sequence)

        switch consume sendResult {
        case .produceMore:
          onProduceMore(Result<Void, Error>.success(()))

        case .enqueueCallback(var callbackHandle):
          callbackHandle.enqueueCallback(onProduceMore: onProduceMore)
        }
      } catch {
        onProduceMore(.failure(error))
      }
    }

    /// Sends the element to the channel.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// provided element. If the channel already terminated then `onProduceMore` will be invoked with
    /// a `Result.failure`.
    ///
    /// - Parameters:
    ///   - element: The element to send to the channel.
    ///   - onProduceMore: The callback which gets invoked once more elements should be produced. This callback might be
    ///   invoked during the call to ``send(_:onProduceMore:)``.
    @inlinable
    public mutating func send(
      _ element: consuming sending Element,
      onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
      do {
        let sendResult = try self.send(element)

        switch consume sendResult {
        case .produceMore:
          onProduceMore(Result<Void, Error>.success(()))

        case .enqueueCallback(var callbackHandle):
          callbackHandle.enqueueCallback(onProduceMore: onProduceMore)
        }
      } catch {
        onProduceMore(.failure(error))
      }
    }

    #if compiler(>=6.2)
    /// Send new elements to the channel.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// first element of the provided sequence. If the channel already terminated then this method will throw an error
    /// indicating the failure.
    ///
    /// This method returns once more elements should be produced.
    ///
    /// - Parameters:
    ///   - sequence: The elements to send to the channel.
    @inlinable
    public mutating nonisolated(nonsending) func send<S>(
      contentsOf sequence: consuming sending S
    ) async throws where Element == S.Element, S: Sequence, Element: Copyable {
      let syncSend: (sending S, inout Self) throws -> SendResult = { try $1.send(contentsOf: $0) }
      let sendResult = try syncSend(sequence, &self)

      switch consume sendResult {
      case .produceMore:
        return ()

      case .enqueueCallback(let callbackToken):
        let id = callbackToken._id
        let storage = self._storage
        try await withTaskCancellationHandler {
          try await withUnsafeThrowingContinuation { continuation in
            self._storage.enqueueProducer(
              callbackToken: id,
              continuation: continuation
            )
          }
        } onCancel: {
          storage.cancelProducer(callbackToken: id)
        }
      }
    }

    /// Send new element to the channel.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// provided element. If the channel already terminated then this method will throw an error
    /// indicating the failure.
    ///
    /// This method returns once more elements should be produced.
    ///
    /// - Parameters:
    ///   - element: The element to send to the channel.
    @inlinable
    public mutating nonisolated(nonsending) func send(_ element: consuming sending Element) async throws {
      let syncSend: (consuming sending Element, inout Self) throws -> SendResult = { try $1.send($0) }
      let sendResult = try syncSend(element, &self)

      switch consume sendResult {
      case .produceMore:
        return ()

      case .enqueueCallback(let callbackHandle):
        let id = callbackHandle._id
        let storage = self._storage
        try await withTaskCancellationHandler {
          try await withUnsafeThrowingContinuation { continuation in
            self._storage.enqueueProducer(
              callbackToken: id,
              continuation: continuation
            )
          }
        } onCancel: {
          storage.cancelProducer(callbackToken: id)
        }
      }
    }

    /// Send the elements of the asynchronous sequence to the channel.
    ///
    /// This method returns once the provided asynchronous sequence or the channel finished.
    ///
    /// - Important: This method does not finish the source if consuming the upstream sequence terminated.
    ///
    /// - Parameters:
    ///   - sequence: The elements to send to the channel.
    @inlinable
    public mutating nonisolated(nonsending) func send<S>(contentsOf sequence: consuming sending S) async throws
    where Element == S.Element, S: AsyncSequence, Element: Copyable, S: Sendable, Element: Sendable {
      for try await element in sequence {
        try await self.send(contentsOf: CollectionOfOne(element))
      }
    }
    #else
    /// Send new elements to the channel.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// first element of the provided sequence. If the channel already terminated then this method will throw an error
    /// indicating the failure.
    ///
    /// This method returns once more elements should be produced.
    ///
    /// - Parameters:
    ///   - sequence: The elements to send to the channel.
    @inlinable
    public mutating func send<S>(
      contentsOf sequence: consuming sending S
    ) async throws where Element == S.Element, S: Sequence, Element: Copyable {
      let syncSend: (sending S, inout Self) throws -> SendResult = { try $1.send(contentsOf: $0) }
      let sendResult = try syncSend(sequence, &self)

      switch consume sendResult {
      case .produceMore:
        return ()

      case .enqueueCallback(let callbackToken):
        let id = callbackToken._id
        let storage = self._storage
        try await withTaskCancellationHandler {
          try await withUnsafeThrowingContinuation { continuation in
            self._storage.enqueueProducer(
              callbackToken: id,
              continuation: continuation
            )
          }
        } onCancel: {
          storage.cancelProducer(callbackToken: id)
        }
      }
    }

    /// Send new element to the channel.
    ///
    /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
    /// provided element. If the channel already terminated then this method will throw an error
    /// indicating the failure.
    ///
    /// This method returns once more elements should be produced.
    ///
    /// - Parameters:
    ///   - element: The element to send to the channel.
    @inlinable
    public mutating func send(_ element: consuming sending Element) async throws {
      let syncSend: (consuming sending Element, inout Self) throws -> SendResult = { try $1.send($0) }
      let sendResult = try syncSend(element, &self)

      switch consume sendResult {
      case .produceMore:
        return ()

      case .enqueueCallback(let callbackHandle):
        let id = callbackHandle._id
        let storage = self._storage
        try await withTaskCancellationHandler {
          try await withUnsafeThrowingContinuation { continuation in
            self._storage.enqueueProducer(
              callbackToken: id,
              continuation: continuation
            )
          }
        } onCancel: {
          storage.cancelProducer(callbackToken: id)
        }
      }
    }

    /// Send the elements of the asynchronous sequence to the channel.
    ///
    /// This method returns once the provided asynchronous sequence or the channel finished.
    ///
    /// - Important: This method does not finish the source if consuming the upstream sequence terminated.
    ///
    /// - Parameters:
    ///   - sequence: The elements to send to the channel.
    @inlinable
    public mutating func send<S>(contentsOf sequence: consuming sending S) async throws
    where Element == S.Element, S: AsyncSequence, Element: Copyable, S: Sendable, Element: Sendable {
      for try await element in sequence {
        try await self.send(contentsOf: CollectionOfOne(element))
      }
    }
    #endif

    /// Indicates that the production terminated.
    ///
    /// After all buffered elements are consumed the subsequent call to ``MultiProducerSingleConsumerAsyncChannel/next(isolation:)`` will return
    /// `nil` or throw an error.
    ///
    /// Calling this function more than once has no effect. After calling finish, the channel enters a terminal state and doesn't accept
    /// new elements.
    ///
    /// - Parameters:
    ///   - error: The error to throw, or `nil`, to finish normally.
    @inlinable
    public consuming func finish(throwing error: Failure? = nil) {
      self._storage.finish(error)
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
extension MultiProducerSingleConsumerAsyncChannel where Element: Copyable {
  struct ChannelAsyncSequence: AsyncSequence {
    @usableFromInline
    final class _Backing: Sendable {
      @usableFromInline
      let storage: MultiProducerSingleConsumerAsyncChannel._Storage

      init(storage: MultiProducerSingleConsumerAsyncChannel._Storage) {
        self.storage = storage
        self.storage.sequenceInitialized()
      }

      deinit {
        self.storage.sequenceDeinitialized()
      }
    }

    @usableFromInline
    let _backing: _Backing

    public func makeAsyncIterator() -> Self.Iterator {
      .init(storage: self._backing.storage)
    }
  }

  /// Converts the channel to an asynchronous sequence for consumption.
  ///
  /// - Important: The returned asynchronous sequence only supports a single iterator to be created and
  /// will fatal error at runtime on subsequent calls to `makeAsyncIterator`.
  public consuming func elements() -> some (AsyncSequence<Element, Failure> & Sendable) {
    ChannelAsyncSequence(_backing: .init(storage: self.storage))
  }
}

@available(AsyncAlgorithms 1.1, *)
extension MultiProducerSingleConsumerAsyncChannel.ChannelAsyncSequence where Element: Copyable {
  struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    final class _Backing {
      @usableFromInline
      let storage: MultiProducerSingleConsumerAsyncChannel._Storage

      init(storage: MultiProducerSingleConsumerAsyncChannel._Storage) {
        self.storage = storage
        self.storage.iteratorInitialized()
      }

      deinit {
        self.storage.iteratorDeinitialized()
      }
    }

    @usableFromInline
    let _backing: _Backing

    init(storage: MultiProducerSingleConsumerAsyncChannel._Storage) {
      self._backing = .init(storage: storage)
    }

    @inlinable
    mutating func next() async throws -> Element? {
      do {
        return try await self._backing.storage.next(isolation: nil)
      } catch {
        throw error as! Failure
      }
    }

    @inlinable
    mutating func next(
      isolation actor: isolated (any Actor)? = #isolation
    ) async throws(Failure) -> Element? {
      do {
        return try await self._backing.storage.next(isolation: actor)
      } catch {
        throw error as! Failure
      }
    }
  }
}

@available(AsyncAlgorithms 1.1, *)
extension MultiProducerSingleConsumerAsyncChannel.ChannelAsyncSequence: Sendable {}
#endif

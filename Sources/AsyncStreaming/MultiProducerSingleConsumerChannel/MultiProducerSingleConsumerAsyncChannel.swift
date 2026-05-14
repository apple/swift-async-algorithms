//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming && compiler(>=6.4)
public import DequeModule
public import ContainersPreview

/// A multi-producer single-consumer channel.
///
/// This is the streaming-oriented variant of
/// ``AsyncAlgorithms.MultiProducerSingleConsumerAsyncChannel``. Instead of
/// exposing the consumer side as an `AsyncSequence`, it offers a chunked
/// ``read(body:)`` method that delivers a noncopyable ``UniqueDeque`` buffer
/// to the caller, so elements move through the channel without copying.
///
/// The channel applies backpressure to producers: it suspends writes when
/// the buffer rises above the high watermark and resumes them once the
/// buffer drops below the low watermark.
///
/// To scope the channel and its initial source to a structured-concurrency
/// region, use ``withChannel(of:withFinalElement:throwing:backpressureStrategy:isolation:body:)``.
///
/// The channel takes a ``FinalElement`` type that it delivers alongside the
/// end-of-stream signal. A producer terminates the channel by calling
/// either ``Source/finish(finalElement:)`` to signal end-of-stream
/// (optionally with a payload) or ``Source/finish(throwing:)`` to terminate
/// with a failure.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct MultiProducerSingleConsumerAsyncChannel<
  Element,
  FinalElement,
  Failure: Error
>: ~Copyable {
  @usableFromInline
  let storage: _Storage

  @usableFromInline
  init(storage: _Storage) {
    self.storage = storage
  }

  /// Creates a new channel and runs `body` with the channel and its initial
  /// source. After `body` returns, the channel finalizes itself and resumes
  /// any remaining suspended producers with an error.
  ///
  /// The channel and source are noncopyable and have no `deinit`-based
  /// cleanup. To terminate the channel before its scope ends, call
  /// ``Source/finish(finalElement:)`` or ``Source/finish(throwing:)`` on a
  /// source. Otherwise `withChannel` finalizes the channel when `body`
  /// returns.
  ///
  /// - Parameters:
  ///   - elementType: The element type of the channel.
  ///   - finalElementType: The end-of-stream payload type of the channel.
  ///   - failureType: The failure type of the channel.
  ///   - backpressureStrategy: The backpressure strategy that the channel uses.
  ///   - isolation: The actor isolation in which `body` runs. Defaults to the caller's isolation.
  ///   - body: A closure that receives ownership of the channel and its initial source.
  /// - Returns: The value returned from `body`.
  @inlinable
  public static func withChannel<Result: ~Copyable, BodyFailure: Error>(
    of elementType: Element.Type = Element.self,
    withFinalElement finalElementType: FinalElement.Type,
    throwing failureType: Failure.Type = Never.self,
    backpressureStrategy: Source.BackpressureStrategy,
    isolation: isolated (any Actor)? = #isolation,
    body: (
      consuming sending MultiProducerSingleConsumerAsyncChannel,
      consuming sending Source
    ) async throws(BodyFailure) -> sending Result
  ) async throws(BodyFailure) -> sending Result {
    let storage = _Storage(
      backpressureStrategy: backpressureStrategy.internalBackpressureStrategy
    )
    let channel = MultiProducerSingleConsumerAsyncChannel(storage: storage)
    let source = Source(storage: storage)
    let result: Result
    do throws(BodyFailure) {
      result = try await body(channel, source)
    } catch {
      storage.finish(throwing: nil, finalElement: nil)
      storage.channelDeinitialized()
      throw error
    }
    storage.finish(throwing: nil, finalElement: nil)
    storage.channelDeinitialized()
    return result
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel where FinalElement == Void {
  /// Creates a new channel with a `Void` end-of-stream payload and runs
  /// `body` with the channel and its initial source.
  ///
  /// This overload is available when ``FinalElement`` is `Void`. It's
  /// equivalent to calling
  /// ``withChannel(of:withFinalElement:throwing:backpressureStrategy:isolation:body:)``
  /// with `withFinalElement: Void.self`.
  public static func withChannel<Result: ~Copyable, BodyFailure: Error>(
    of elementType: Element.Type = Element.self,
    throwing failureType: Failure.Type = Never.self,
    backpressureStrategy: Source.BackpressureStrategy,
    isolation: isolated (any Actor)? = #isolation,
    body: (
      consuming sending MultiProducerSingleConsumerAsyncChannel,
      consuming sending Source
    ) async throws(BodyFailure) -> sending Result
  ) async throws(BodyFailure) -> sending Result {
    try await self.withChannel(
      of: elementType,
      withFinalElement: Void.self,
      throwing: failureType,
      backpressureStrategy: backpressureStrategy,
      isolation: isolation,
      body: body
    )
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel {
  /// A handle for sending elements to the channel.
  public struct Source: ~Copyable, Sendable {
    /// A backpressure strategy for the channel.
    public struct BackpressureStrategy: Sendable {
      @usableFromInline
      var internalBackpressureStrategy: _InternalBackpressureStrategy

      @inlinable
      init(internalBackpressureStrategy: _InternalBackpressureStrategy) {
        self.internalBackpressureStrategy = internalBackpressureStrategy
      }

      /// A backpressure strategy that suspends and resumes producers based on
      /// high and low watermarks.
      ///
      /// - Parameters:
      ///   - low: When the buffered element count drops below this watermark, the channel resumes suspended producers.
      ///   - high: When the buffered element count rises above this watermark, the channel suspends new writes.
      @inlinable
      public static func watermark(low: Int, high: Int) -> BackpressureStrategy {
        .init(
          internalBackpressureStrategy: .watermark(
            .init(low: low, high: high, waterLevelForElement: nil)
          )
        )
      }

      /// A backpressure strategy that suspends and resumes producers based on
      /// high and low watermarks, weighted by a per-element water level.
      ///
      /// - Parameters:
      ///   - low: When the water level drops below this watermark, the channel resumes suspended producers.
      ///   - high: When the water level rises above this watermark, the channel suspends new writes.
      ///   - waterLevelForElement: A closure that returns the water-level
      ///     contribution of a single element. The channel calls this closure
      ///     while holding its lock, so the closure must be free of side
      ///     effects and should run in constant time.
      @inlinable
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

    @usableFromInline
    enum _SendResult: ~Copyable, Sendable {
      case produceMore
      case enqueueCallback(callbackToken: UInt64)
    }

    @usableFromInline
    let _storage: _Storage

    @usableFromInline
    let _id: UInt64

    @usableFromInline
    init(storage: _Storage) {
      self._storage = storage
      self._id = self._storage.sourceInitialized()
    }

    /// Sets a callback to invoke when the channel terminates.
    ///
    /// The channel calls `callback` after the reader observes its last element.
    /// If the channel has already terminated, the channel invokes `callback`
    /// immediately.
    ///
    /// - Important: A source supports a single termination callback. Setting a
    ///   new callback replaces any previous one.
    @inlinable
    public func setOnTerminationCallback(_ callback: (@Sendable () -> Void)?) {
      self._storage.setOnTerminationCallback(sourceID: self._id, callback: callback)
    }

    /// Creates an additional source for sending elements to the channel
    /// concurrently from multiple producers.
    @inlinable
    public mutating func clone() -> sending Self {
      .init(storage: self._storage)
    }

    /// Terminates the channel with the supplied error.
    ///
    /// After the reader consumes all buffered elements, the next call to
    /// ``MultiProducerSingleConsumerAsyncChannel/read(body:)`` throws `error`.
    /// This path delivers no ``FinalElement`` payload to the reader.
    ///
    /// To terminate the channel cleanly with an end-of-stream payload, call
    /// ``finish(finalElement:)`` instead. When ``FinalElement`` is `Void`,
    /// you can also call the ``finish()`` convenience.
    @inlinable
    public consuming func finish(throwing error: Failure) {
      self._storage.finish(throwing: error, finalElement: nil)
    }

    /// Finishes the channel with an optional ``FinalElement`` payload.
    ///
    /// The reader observes end-of-stream as a non-`nil` `finalElement`
    /// argument to the body of its next
    /// ``MultiProducerSingleConsumerAsyncChannel/read(body:)`` call. The
    /// channel delivers any elements still buffered from earlier
    /// ``write(buffer:)`` calls before the terminator.
    ///
    /// - Note: This method delivers only the end-of-stream signal. To send a
    ///   final batch of elements alongside the terminator, call
    ///   ``write(buffer:)`` first and then ``finish(finalElement:)``.
    @inlinable
    public consuming func finish(finalElement: consuming sending FinalElement?) {
      self._storage.finish(throwing: nil, finalElement: finalElement)
    }

    /// Writes every element of `buffer` to the channel.
    ///
    /// On success the call drains `buffer` completely. If the channel's
    /// backpressure strategy signals that production should pause, the call
    /// suspends until the reader drains enough of the channel to fall below
    /// the low watermark.
    ///
    /// - Throws: ``MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError``
    ///   if the channel has already finished, or `CancellationError` if the
    ///   task is canceled while suspended on backpressure.
    @inlinable
    public mutating func write<Buffer: RangeReplaceableContainer<Element> & ~Copyable & Sendable>(
      buffer: inout sending Buffer
    ) async throws {
      let sendResult: _SendResult
      do {
        sendResult = try self._storage.write(buffer: &buffer)
      } catch {
        throw error
      }

      switch consume sendResult {
      case .produceMore:
        return

      case .enqueueCallback(let token):
        let storage = self._storage
        do {
          try await withTaskCancellationHandler {
            try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
              storage.enqueueProducer(callbackToken: token, continuation: continuation)
            }
          } onCancel: {
            storage.cancelProducer(callbackToken: token)
          }
        } catch {
          throw error
        }
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel.Source where FinalElement == Void {
  /// Finishes the channel with an empty `Void` end-of-stream payload.
  ///
  /// This method is equivalent to calling ``finish(finalElement:)`` with
  /// `.some(())`. The reader observes end-of-stream as a non-`nil`
  /// `finalElement` argument to the body of its next read.
  @inlinable
  public consuming func finish() {
    self._storage.finish(throwing: nil, finalElement: .some(()))
  }
}

// MARK: - Reading

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel {
  /// Reads the next chunk of elements from the channel.
  ///
  /// The channel passes the buffered elements to `body` along with an
  /// optional ``FinalElement`` payload. A non-`nil` `finalElement` marks
  /// the chunk as terminal and delivers the end-of-stream signal. The
  /// terminal chunk's buffer may be empty or contain a final batch of
  /// elements.
  ///
  /// - Throws: An ``EitherError`` whose outer `.first` arm carries a
  ///   read-side error — either the channel's `Failure` (when a producer
  ///   called ``Source/finish(throwing:)``) or a `CancellationError` (when
  ///   the task is canceled while suspended in `read`) — and whose outer
  ///   `.second` arm carries the failure thrown by `body`.
  ///
  /// - Important: After the reader observes a non-`nil` `finalElement`,
  ///   calling `read(body:)` again is a programmer error.
  @inlinable
  public mutating func read<Return: ~Copyable, BodyFailure: Error>(
    body: (inout UniqueDeque<Element>, consuming FinalElement?) async throws(BodyFailure) -> Return
  ) async throws(EitherError<EitherError<Failure, CancellationError>, BodyFailure>) -> Return {
    while true {
      let action = self.storage.readAvailable()
      switch consume action {
      case .returnElements(let disconnected):
        var buffer = disconnected.take()
        let result: Return
        do throws(BodyFailure) {
          result = try await body(&buffer, nil)
          // TODO: This should not be necessary
          nonisolated(unsafe) let buffer = buffer
          self.storage.returnCachedReadBuffer(buffer)
        } catch {
          // TODO: This should not be necessary
          nonisolated(unsafe) let buffer = buffer
          self.storage.returnCachedReadBuffer(buffer)
          throw .second(error)
        }
        return result

      case .returnElementsAndResumeProducers(let disconnected, let producers):
        var buffer = disconnected.take()
        for producer in producers {
          switch producer {
          case .closure(let onProduceMore):
            onProduceMore(Result<Void, any Error>.success(()))
          case .continuation(let continuation):
            continuation.resume()
          }
        }
        let result: Return
        do throws(BodyFailure) {
          result = try await body(&buffer, nil)
          // TODO: This should not be necessary
          nonisolated(unsafe) let buffer = buffer
          self.storage.returnCachedReadBuffer(buffer)
        } catch {
          // TODO: This should not be necessary
          nonisolated(unsafe) let buffer = buffer
          self.storage.returnCachedReadBuffer(buffer)
          throw .second(error)
        }
        return result

      case .returnTerminalChunk(let disconnectedBuffer, let disconnectedFinal, let onTerminations):
        for (_, callback) in onTerminations { callback() }
        var buffer = disconnectedBuffer.take()
        let final = disconnectedFinal.take()
        do throws(BodyFailure) {
          return try await body(&buffer, final)
        } catch {
          throw .second(error)
        }

      case .throwFailure(let failure, let onTerminations):
        for (_, callback) in onTerminations { callback() }
        if let failure {
          throw .first(.first(failure))
        }
        var empty = UniqueDeque<Element>()
        do throws(BodyFailure) {
          return try await body(&empty, nil)
        } catch {
          throw .second(error)
        }

      case .returnNil:
        var empty = UniqueDeque<Element>()
        do throws(BodyFailure) {
          return try await body(&empty, nil)
        } catch {
          throw .second(error)
        }

      case .suspend:
        do {
          try await self.storage.suspendRead()
        } catch {
          throw .first(error)
        }
        continue
      }
    }
  }
}

/// An error that ``MultiProducerSingleConsumerAsyncChannel/Source/write(buffer:)``
/// throws when its source has already finished.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError: Error {
  @usableFromInline
  init() {}
}
#endif

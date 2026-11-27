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

public import SpanPreview
public import DequeModule
public import ContainersPreview
public import BasicContainers

/// A bidirectional, in-memory duplex channel with four connected handles.
///
/// Each call to ``withDuplex(of:withFinalElement:throwing:backpressureStrategy:isolation:body:)``
/// creates two ``Writer``s and two ``Reader``s connected by a pair of
/// internal ``MultiProducerSingleConsumerAsyncChannel`` storages — one
/// per direction:
///
/// ```
///                         forward
///   writerA ────────────────────────────────────────> readerB
///
///                         reverse
///   readerA <──────────────────────────────────────── writerB
/// ```
///
/// The four handles are independent `~Copyable` values so each can be
/// sent to its own task without an intermediate decomposition step.
///
/// Each direction applies backpressure independently using the configured
/// ``BackpressureStrategy``: writes suspend when the per-direction buffer
/// rises above the high watermark and resume once it drops below the low
/// watermark.
///
///
/// To scope the channel and its handles to a structured-concurrency
/// region, use
/// ``withDuplex(of:withFinalElement:throwing:backpressureStrategy:isolation:body:)``.
/// When `body` returns, both directions are finalized and any remaining
/// suspended producers are resumed with an error.
///
/// The ``FinalElement`` and ``Failure`` types apply to both directions.
/// Each direction's writer terminates its half of the channel
/// independently by calling ``Writer/finish(finalElement:)`` or
/// ``Writer/finish(throwing:)``.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
public struct DuplexAsyncChannel<
  Element: Sendable,
  FinalElement: Sendable,
  Failure: Error
>: ~Copyable {
  /// Creates a new duplex channel with four connected handles and runs
  /// `body` with all four.
  ///
  /// The handles are paired by side:
  ///
  /// - `writerA` and `readerA` belong to side A. Elements `writerA`
  ///   sends are observed on `readerB`; `readerA` observes elements
  ///   `writerB` sends.
  /// - `writerB` and `readerB` belong to side B, mirrored.
  ///
  /// After `body` returns, the duplex finalizes both directions and
  /// resumes any remaining suspended producers with an error.
  ///
  /// The handles are noncopyable and have no `deinit`-based cleanup. To
  /// terminate one direction before the scope ends, call
  /// ``Writer/finish(finalElement:)`` or ``Writer/finish(throwing:)`` on
  /// the corresponding writer. Otherwise `withDuplex` finalizes both
  /// directions when `body` returns.
  ///
  /// - Parameters:
  ///   - elementType: The element type of both directions.
  ///   - finalElementType: The end-of-stream payload type of both
  ///     directions.
  ///   - failureType: The failure type of both directions.
  ///   - backpressureStrategy: The backpressure strategy applied
  ///     independently to each direction.
  ///   - isolation: The actor isolation in which `body` runs. Defaults to
  ///     the caller's isolation.
  ///   - body: A closure that receives ownership of the four connected
  ///     handles, in order: side A's writer, side A's reader, side B's
  ///     writer, side B's reader.
  /// - Returns: The value returned from `body`.
  @inlinable
  public static func withDuplex<Result: ~Copyable, BodyFailure: Error>(
    of elementType: Element.Type = Element.self,
    withFinalElement finalElementType: FinalElement.Type,
    throwing failureType: Failure.Type = Never.self,
    backpressureStrategy: BackpressureStrategy,
    isolation: isolated (any Actor)? = #isolation,
    body: (
      consuming sending Writer,
      consuming sending Reader,
      consuming sending Writer,
      consuming sending Reader
    ) async throws(BodyFailure) -> sending Result
  ) async throws(BodyFailure) -> sending Result {
    let forward = MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._Storage(
      backpressureStrategy: backpressureStrategy.internalBackpressureStrategy
    )
    let reverse = MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._Storage(
      backpressureStrategy: backpressureStrategy.internalBackpressureStrategy
    )

    let writerA = Writer(storage: forward)
    let readerA = Reader(storage: reverse)
    let writerB = Writer(storage: reverse)
    let readerB = Reader(storage: forward)

    let result: Result
    do throws(BodyFailure) {
      result = try await body(writerA, readerA, writerB, readerB)
    } catch {
      forward.finish(throwing: nil, finalElement: nil)
      reverse.finish(throwing: nil, finalElement: nil)
      forward.channelDeinitialized()
      reverse.channelDeinitialized()
      throw error
    }
    forward.finish(throwing: nil, finalElement: nil)
    reverse.finish(throwing: nil, finalElement: nil)
    forward.channelDeinitialized()
    reverse.channelDeinitialized()
    return result
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension DuplexAsyncChannel where FinalElement == Void {
  /// Creates a new duplex channel with a `Void` end-of-stream payload and
  /// runs `body` with all four handles.
  ///
  /// This overload is available when ``FinalElement`` is `Void`. It's
  /// equivalent to calling
  /// ``withDuplex(of:withFinalElement:throwing:backpressureStrategy:isolation:body:)``
  /// with `withFinalElement: Void.self`.
  @inlinable
  public static func withDuplex<Result: ~Copyable, BodyFailure: Error>(
    of elementType: Element.Type = Element.self,
    throwing failureType: Failure.Type = Never.self,
    backpressureStrategy: BackpressureStrategy,
    isolation: isolated (any Actor)? = #isolation,
    body: (
      consuming sending Writer,
      consuming sending Reader,
      consuming sending Writer,
      consuming sending Reader
    ) async throws(BodyFailure) -> sending Result
  ) async throws(BodyFailure) -> sending Result {
    try await self.withDuplex(
      of: elementType,
      withFinalElement: Void.self,
      throwing: failureType,
      backpressureStrategy: backpressureStrategy,
      isolation: isolation,
      body: body
    )
  }
}

// MARK: - Backpressure strategy

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension DuplexAsyncChannel {
  /// A backpressure strategy applied independently to each direction of
  /// the duplex.
  public struct BackpressureStrategy: Sendable {
    @usableFromInline
    var internalBackpressureStrategy:
      MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._InternalBackpressureStrategy

    @inlinable
    init(
      internalBackpressureStrategy:
        MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._InternalBackpressureStrategy
    ) {
      self.internalBackpressureStrategy = internalBackpressureStrategy
    }

    /// A backpressure strategy that suspends and resumes producers based
    /// on high and low watermarks.
    ///
    /// - Parameters:
    ///   - low: When the buffered element count drops below this
    ///     watermark, the channel resumes suspended producers in that
    ///     direction.
    ///   - high: When the buffered element count rises above this
    ///     watermark, the channel suspends new writes in that direction.
    @inlinable
    public static func watermark(low: Int, high: Int) -> BackpressureStrategy {
      .init(
        internalBackpressureStrategy: .watermark(
          .init(low: low, high: high, waterLevelForElement: nil)
        )
      )
    }

    /// A backpressure strategy that suspends and resumes producers based
    /// on high and low watermarks, weighted by a per-element water level.
    ///
    /// - Parameters:
    ///   - low: When the water level drops below this watermark, the
    ///     channel resumes suspended producers in that direction.
    ///   - high: When the water level rises above this watermark, the
    ///     channel suspends new writes in that direction.
    ///   - waterLevelForElement: A closure that returns the water-level
    ///     contribution of a single element. The channel calls this
    ///     closure while holding its lock, so the closure must be free of
    ///     side effects and should run in constant time.
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
}

// MARK: - Writer

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension DuplexAsyncChannel {
  /// The writer half of one side of a ``DuplexAsyncChannel``.
  ///
  /// Conforms to ``CallerAsyncWriter``: callers lend a `Span` of elements
  /// that the writer copies into the channel.
  ///
  /// Elements written here travel the channel's forward or reverse
  /// direction and are observed on the peer side's ``Reader``. The writer
  /// applies backpressure: ``write(_:)`` suspends when the
  /// destination's buffer rises above the configured high watermark.
  ///
  /// Writers can be cloned with ``clone()`` to produce concurrently from
  /// multiple tasks. Terminate the direction with
  /// ``finish(_:finalElement:)``, ``finish(finalElement:)``, or
  /// ``finish(throwing:)``.
  public struct Writer: ~Copyable, CallerAsyncWriter {
    public typealias WriteElement = Element
    public typealias WriteFailure = any Error
    @usableFromInline
    let _storage: MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._Storage

    @usableFromInline
    let _id: UInt64

    @usableFromInline
    init(
      storage: MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._Storage
    ) {
      self._storage = storage
      self._id = storage.sourceInitialized()
    }

    /// Sets a callback to invoke when this direction terminates.
    ///
    /// The duplex calls `callback` after the peer's reader observes its
    /// last element on this direction. If the direction has already
    /// terminated, the duplex invokes `callback` immediately.
    ///
    /// - Important: A writer supports a single termination callback.
    ///   Setting a new callback replaces any previous one.
    @inlinable
    public func setOnTerminationCallback(_ callback: (@Sendable () -> Void)?) {
      self._storage.setOnTerminationCallback(sourceID: self._id, callback: callback)
    }

    /// Creates an additional writer for this direction so multiple
    /// producers can send concurrently.
    ///
    /// The cloned writer terminates the direction independently — the
    /// direction stays open until every clone has finished or been
    /// dropped, mirroring ``MultiProducerSingleConsumerAsyncChannel/Source/clone()``.
    @inlinable
    public mutating func clone() -> sending Self {
      .init(storage: self._storage)
    }

    /// Terminates this direction with the supplied error.
    ///
    /// After the peer reader consumes all buffered elements on this
    /// direction, its next ``Reader/read(maxCount:body:)`` call throws `error`.
    /// This path delivers no ``FinalElement`` payload to the peer.
    ///
    /// To terminate this direction cleanly with an end-of-stream payload,
    /// call ``finish(finalElement:)`` instead. When ``FinalElement`` is
    /// `Void`, you can also call the ``finish()`` convenience.
    @inlinable
    public consuming func finish(throwing error: Failure) {
      self._storage.finish(throwing: error, finalElement: nil)
    }

    /// Finishes this direction with a ``FinalElement`` payload.
    ///
    /// The peer reader observes end-of-stream as a non-`nil` `finalElement`
    /// argument to the body of its next ``Reader/read(maxCount:body:)`` call. The
    /// channel delivers any elements still buffered from earlier
    /// ``write(_:)`` calls before the terminator.
    ///
    /// - Note: This method delivers only the end-of-stream signal. To
    ///   send a final batch of elements alongside the terminator, call
    ///   ``write(_:)`` first and then ``finish(finalElement:)``.
    @inlinable
    public consuming func finish(finalElement: consuming sending FinalElement) {
      self._storage.finish(throwing: nil, finalElement: finalElement)
    }

    /// Writes copies of all `elements` to this direction.
    ///
    /// If the direction's backpressure strategy signals that production
    /// should pause, the call suspends until the peer reader drains enough
    /// of the channel to fall below the low watermark.
    ///
    /// - Throws: ``MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError``
    ///   if this direction has already finished, or `CancellationError`
    ///   if the task is canceled while suspended on backpressure.
    @inlinable
    public mutating func write(_ elements: Span<Element>) async throws {
      guard !elements.isEmpty else { return }
      let sendResult = try self._storage.write(elements)

      switch consume sendResult {
      case .produceMore:
        return

      case .enqueueCallback(let token):
        let storage = self._storage
        try await withTaskCancellationHandler {
          try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
            storage.enqueueProducer(callbackToken: token, continuation: continuation)
          }
        } onCancel: {
          storage.cancelProducer(callbackToken: token)
        }
      }
    }

    /// Writes copies of the remaining `elements`, then signals
    /// end-of-stream with the ``FinalElement`` payload. Consumes the writer.
    ///
    /// This is the ``CallerAsyncWriter`` entry point.
    @inlinable
    public consuming func finish(
      _ elements: Span<Element>,
      finalElement: consuming FinalElement
    ) async throws {
      if !elements.isEmpty {
        try await self.write(elements)
      }
      self._storage.finish(throwing: nil, finalElement: finalElement)
    }
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension DuplexAsyncChannel.Writer where FinalElement == Void {
  /// Finishes this direction with an empty `Void` end-of-stream payload.
  ///
  /// This method is equivalent to calling ``finish(finalElement:)`` with
  /// `()`. The peer reader observes end-of-stream as a non-`nil`
  /// `finalElement` argument to the body of its next read.
  @inlinable
  public consuming func finish() {
    self._storage.finish(throwing: nil, finalElement: ())
  }
}

// MARK: - Reader

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension DuplexAsyncChannel {
  /// The reader half of one side of a ``DuplexAsyncChannel``.
  ///
  /// Conforms to ``AsyncReader``: the reader lends an `InputSpan` of elements to
  /// the body closure alongside an optional ``FinalElement`` payload that
  /// signals end-of-stream when present.
  ///
  /// The channel stores its elements in a double ended queue that can wrap
  /// around, so the span covers the first contiguous segment. The elements
  /// the body doesn't see are delivered by the following reads.
  ///
  /// Reads elements written by the peer side's ``Writer``.
  public struct Reader: ~Copyable, AsyncReader {
    public typealias ReadElement = Element
    public typealias ReadFailure = EitherError<Failure, CancellationError>
    @usableFromInline
    let _storage: MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._Storage

    /// Elements of a terminal chunk that did not fit into the first
    /// contiguous span, together with the payload that ends the stream.
    @usableFromInline
    var _carry: UniqueDeque<Element>?

    @usableFromInline
    var _carryFinal: FinalElement?

    @usableFromInline
    init(
      storage: MultiProducerSingleConsumerAsyncChannel<Element, FinalElement, Failure>._Storage
    ) {
      self._storage = storage
      self._carry = nil
      self._carryFinal = nil
    }

    /// Lends the first contiguous segment of `buffer`, at most `maxCount`
    /// elements, to `body`.
    ///
    /// A double ended queue can wrap around, so the elements are not always
    /// one span. The elements that remain are given back to the channel, or,
    /// for the terminal chunk, kept in the reader for the next read.
    @inlinable
    mutating func _deliver<Return: ~Copyable, BodyFailure: Error>(
      _ buffer: consuming UniqueDeque<Element>,
      final: consuming FinalElement?,
      returnToChannel: Bool,
      maxCount: Int,
      body: (inout InputSpan<Element>, consuming FinalElement?) async throws(BodyFailure) -> Return
    ) async throws(EitherError<EitherError<Failure, CancellationError>, BodyFailure>) -> Return {
      var buffer = buffer
      var final = final
      var index = 0
      let count = buffer.nextSpan(after: &index, maxCount: maxCount, limitedBy: buffer.count).count
      let isLast = count == buffer.count
      var result: Return? = nil
      var bodyFailure: BodyFailure? = nil
      do {
        // The consumer removes the delivered elements from the buffer when it
        // is destroyed at the end of this scope. An empty deque may have no
        // storage, so it gets an empty span instead.
        if count > 0 {
          var consumer = buffer.consumeSubrange(0..<count)
          var elements = consumer.drainNext(maxCount: count)
          do throws(BodyFailure) {
            result = try await body(&elements, isLast ? final.take() : nil)
          } catch {
            bodyFailure = error
          }
        } else {
          var elements = InputSpan<Element>()
          do throws(BodyFailure) {
            result = try await body(&elements, isLast ? final.take() : nil)
          } catch {
            bodyFailure = error
          }
        }
      }
      if returnToChannel {
        self._storage.returnCachedReadBuffer(buffer)
      } else if bodyFailure == nil, !isLast {
        self._carry = consume buffer
        self._carryFinal = final.take()
      }
      if let bodyFailure {
        throw .second(bodyFailure)
      }
      // The force-unwrap is safe since the body returned without throwing.
      return result.take()!
    }

    @inlinable
    public mutating func read<Return: ~Copyable, BodyFailure: Error>(
      maxCount: Int,
      body: (inout InputSpan<Element>, consuming FinalElement?) async throws(BodyFailure) -> Return
    ) async throws(EitherError<EitherError<Failure, CancellationError>, BodyFailure>) -> Return {
      precondition(maxCount > 0, "maxCount must be greater than zero")
      if let carry = self._carry.take() {
        return try await self._deliver(
          carry,
          final: self._carryFinal.take(),
          returnToChannel: false,
          maxCount: maxCount,
          body: body
        )
      }
      while true {
        let action = self._storage.readAvailable()
        switch consume action {
        case .returnElements(let disconnected):
          return try await self._deliver(
            disconnected.take(),
            final: nil,
            returnToChannel: true,
            maxCount: maxCount,
            body: body
          )

        case .returnElementsAndResumeProducers(let disconnected, let producers):
          let buffer = disconnected.take()
          for producer in producers {
            switch producer {
            case .closure(let onProduceMore):
              onProduceMore(Result<Void, any Error>.success(()))
            case .continuation(let continuation):
              continuation.resume()
            }
          }
          return try await self._deliver(buffer, final: nil, returnToChannel: true, maxCount: maxCount, body: body)

        case .returnTerminalChunk(let disconnectedBuffer, let disconnectedFinal, let onTerminations):
          for (_, callback) in onTerminations { callback() }
          return try await self._deliver(
            disconnectedBuffer.take(),
            final: disconnectedFinal.take(),
            returnToChannel: false,
            maxCount: maxCount,
            body: body
          )

        case .throwFailure(let failure, let onTerminations):
          for (_, callback) in onTerminations { callback() }
          if let failure {
            throw .first(.first(failure))
          }
          do throws(BodyFailure) {
            var empty = InputSpan<Element>()
            return try await body(&empty, nil)
          } catch {
            throw .second(error)
          }

        case .throwCancellation:
          throw .first(.second(CancellationError()))

        case .suspend:
          do {
            try await self._storage.suspendRead()
          } catch {
            throw .first(error)
          }
          continue
        }
      }
    }
  }
}
#endif

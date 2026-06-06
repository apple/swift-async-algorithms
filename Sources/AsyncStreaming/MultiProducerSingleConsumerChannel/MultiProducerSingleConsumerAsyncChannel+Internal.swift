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
public import Synchronization
public import ContainersPreview

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel {
  @usableFromInline
  enum _InternalBackpressureStrategy: Sendable, CustomStringConvertible {
    @usableFromInline
    struct _Watermark: Sendable, CustomStringConvertible {
      @usableFromInline
      let _low: Int

      @usableFromInline
      let _high: Int

      @usableFromInline
      var _currentWatermark: Int = 0

      @usableFromInline
      let _waterLevelForElement: (@Sendable (borrowing Element) -> Int)?

      @usableFromInline
      var description: String { "watermark(\(self._currentWatermark))" }

      @inlinable
      init(low: Int, high: Int, waterLevelForElement: (@Sendable (borrowing Element) -> Int)?) {
        precondition(low <= high)
        self._low = low
        self._high = high
        self._waterLevelForElement = waterLevelForElement
      }

      /// Records that elements at offsets `appendedFromOffset..<buffer.count`
      /// have been appended to `buffer`. Returns whether more should be produced.
      @inlinable
      mutating func didSend(buffer: borrowing UniqueDeque<Element>, appendedFromOffset offset: Int) -> Bool {
        if let f = self._waterLevelForElement {
          for i in offset..<buffer.count {
            self._currentWatermark += f(buffer[i])
          }
        } else {
          self._currentWatermark += buffer.count - offset
        }
        precondition(self._currentWatermark >= 0)
        return self._currentWatermark < self._high
      }

      /// Records that all elements in `buffer` are about to leave the channel.
      /// Returns whether more should be produced now.
      @inlinable
      mutating func didConsume(buffer: borrowing UniqueDeque<Element>) -> Bool {
        if let f = self._waterLevelForElement {
          for i in 0..<buffer.count {
            self._currentWatermark -= f(buffer[i])
          }
        } else {
          self._currentWatermark -= buffer.count
        }
        precondition(self._currentWatermark >= 0)
        return self._currentWatermark < self._low
      }
    }

    case watermark(_Watermark)

    @usableFromInline
    var description: String {
      switch consume self {
      case .watermark(let s): return s.description
      }
    }

    @inlinable
    mutating func didSend(buffer: borrowing UniqueDeque<Element>, appendedFromOffset offset: Int) -> Bool {
      switch consume self {
      case .watermark(var s):
        let r = s.didSend(buffer: buffer, appendedFromOffset: offset)
        self = .watermark(s)
        return r
      }
    }

    @inlinable
    mutating func didConsume(buffer: borrowing UniqueDeque<Element>) -> Bool {
      switch consume self {
      case .watermark(var s):
        let r = s.didConsume(buffer: buffer)
        self = .watermark(s)
        return r
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel {
  @usableFromInline
  final class _Storage: Sendable {
    @usableFromInline
    let _stateMachine: Mutex<_StateMachine>

    @inlinable
    init(backpressureStrategy: _InternalBackpressureStrategy) {
      self._stateMachine = Mutex<_StateMachine>(_StateMachine(backpressureStrategy: backpressureStrategy))
    }

    @inlinable
    func setOnTerminationCallback(sourceID: UInt64, callback: (@Sendable () -> Void)?) {
      let action = self._stateMachine.withLock {
        $0.setOnTerminationCallback(sourceID: sourceID, callback: callback)
      }
      switch action {
      case .callOnTermination(let onTermination):
        onTermination()
      case .none:
        break
      }
    }

    @inlinable
    func channelDeinitialized() {
      let action = self._stateMachine.withLock { $0.channelDeinitialized() }
      switch action {
      case .callOnTerminations(let onTerminations):
        for (_, cb) in onTerminations { cb() }
      case .failProducersAndCallOnTerminations(let producers, let onTerminations):
        Self._failProducers(producers)
        for (_, cb) in onTerminations { cb() }
      case .none:
        break
      }
    }

    func sourceInitialized() -> UInt64 {
      self._stateMachine.withLock { $0.sourceInitialized() }
    }

    @inlinable
    func write<Buffer: RangeReplaceableContainer<Element> & ~Copyable>(
      buffer: inout sending Buffer
    ) throws -> MultiProducerSingleConsumerAsyncChannel.Source._SendResult {
      var disconnectedBuffer = _Disconnected(value: Optional(buffer))
      let action = self._stateMachine.withLock {
        var buffer = disconnectedBuffer.swap(newValue: nil)!
        let action = $0.send(buffer: &buffer)
        disconnectedBuffer.swap(newValue: buffer)
        return action
      }
      buffer = disconnectedBuffer.take()!

      switch consume action {
      case .returnProduceMore:
        return .produceMore
      case .returnEnqueue(let token):
        return .enqueueCallback(callbackToken: token)
      case .resumeReaderAndReturnProduceMore(let continuation):
        continuation.resume()
        return .produceMore
      case .resumeReaderAndReturnEnqueue(let continuation, let token):
        continuation.resume()
        return .enqueueCallback(callbackToken: token)
      case .throwFinishedError:
        throw MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()
      }
    }

    @inlinable
    func enqueueProducer(callbackToken: UInt64, continuation: UnsafeContinuation<Void, any Error>) {
      let action = self._stateMachine.withLock {
        $0.enqueueContinuation(callbackToken: callbackToken, continuation: continuation)
      }
      switch action {
      case .resumeProducer(let c):
        c.resume()
      case .resumeProducerWithError(let c, let err):
        c.resume(throwing: err)
      case .none:
        break
      }
    }

    @inlinable
    func enqueueProducer(
      callbackToken: UInt64,
      onProduceMore: sending @escaping (Result<Void, any Error>) -> Void
    ) {
      var optionalCallback = _Disconnected(value: Optional(onProduceMore))
      let action = self._stateMachine.withLock {
        let cb = optionalCallback.swap(newValue: nil)!
        return $0.enqueueProducer(callbackToken: callbackToken, onProduceMore: cb)
      }
      switch consume action {
      case .resumeProducer(let cb):
        cb.take()(.success(()))
      case .resumeProducerWithError(let cb, let err):
        cb.take()(.failure(err))
      case .none:
        break
      }
    }

    @inlinable
    func cancelProducer(callbackToken: UInt64) {
      let action = self._stateMachine.withLock { $0.cancelProducer(callbackToken: callbackToken) }
      switch action {
      case .resumeProducerWithCancellationError(let p):
        switch p {
        case .closure(let cb):
          cb(.failure(CancellationError()))
        case .continuation(let c):
          c.resume(throwing: CancellationError())
        }
      case .none:
        break
      }
    }

    @inlinable
    func finish(throwing failure: Failure?, finalElement: consuming sending FinalElement?) {
      var optionalFinal = Optional(_Disconnected(value: finalElement))
      let action = self._stateMachine.withLock {
        let fe = optionalFinal.take()!.take()
        return $0.finish(failure: failure, finalElement: fe)
      }
      switch action {
      case .callOnTerminations(let onTerminations):
        for (_, cb) in onTerminations { cb() }
      case .resumeProducers(let producers):
        Self._failProducers(producers)
      case .resumeReaderAndResumeProducers(let reader, let producers):
        reader.resume()
        Self._failProducers(producers)
      case .none:
        break
      }
    }

    @inlinable
    func readAvailable() -> _StateMachine.ReadAvailableAction {
      self._stateMachine.withLock { $0.readAvailable() }
    }

    @inlinable
    func returnCachedReadBuffer(_ buffer: consuming sending UniqueDeque<Element>) {
      var disconnected = Optional(_Disconnected(value: buffer))
      self._stateMachine.withLock {
        $0.returnCachedReadBuffer(disconnected.take()!.take())
      }
    }

    @inlinable
    func suspendRead() async throws(EitherError<Failure, CancellationError>) {
      try await withTaskCancellationHandler { () throws(EitherError<Failure, CancellationError>) -> Void in
        try await withUnsafeThrowingContinuation {
          (continuation: UnsafeContinuation<Void, EitherError<Failure, CancellationError>>) in
          let action = self._stateMachine.withLock {
            $0.suspendRead(continuation: continuation)
          }
          switch consume action {
          case .resumeReader(let c):
            c.resume()
          case .none:
            break
          }
        }
      } onCancel: {
        let action = self._stateMachine.withLock { $0.cancelRead() }
        switch action {
        case .resumeReaderWithCancellationError(let c, let producers, let onTerminations):
          c.resume(throwing: .second(CancellationError()))
          Self._failProducers(producers)
          for (_, cb) in onTerminations { cb() }
        case .failProducersAndCallOnTerminations(let producers, let onTerminations):
          Self._failProducers(producers)
          for (_, cb) in onTerminations { cb() }
        case .none:
          break
        }
      }
    }

    @inlinable
    static func _failProducers(_ producers: [_MultiProducerSingleConsumerSuspendedProducer]) {
      for p in producers {
        switch p {
        case .closure(let cb):
          cb(.failure(MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()))
        case .continuation(let c):
          c.resume(throwing: MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
        }
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel._Storage {
  @usableFromInline
  struct _StateMachine: ~Copyable, Sendable {
    @usableFromInline
    var _state: _State

    @inlinable
    init(backpressureStrategy: MultiProducerSingleConsumerAsyncChannel._InternalBackpressureStrategy) {
      self._state = .channeling(
        .init(
          backpressureStrategy: backpressureStrategy,
          buffer: _Disconnected(value: UniqueDeque<Element>()),
          producerContinuations: .init(),
          cancelledAsyncProducers: .init(),
          hasOutstandingDemand: true,
          nextCallbackTokenID: 0,
          nextSourceID: 0
        )
      )
    }

    @inlinable
    init(state: consuming _State) {
      self._state = state
    }

    @usableFromInline
    enum SetOnTerminationCallback: Sendable {
      case callOnTermination(@Sendable () -> Void)
    }

    @inlinable
    mutating func setOnTerminationCallback(
      sourceID: UInt64,
      callback: (@Sendable () -> Void)?
    ) -> SetOnTerminationCallback? {
      switch consume self._state {
      case .channeling(var s):
        Self._upsertOnTermination(&s.onTerminations, sourceID: sourceID, callback: callback)
        self = .init(state: .channeling(s))
        return .none

      case .sourceFinished(var s):
        Self._upsertOnTermination(&s.onTerminations, sourceID: sourceID, callback: callback)
        self = .init(state: .sourceFinished(s))
        return .none

      case .finished(let s):
        self = .init(state: .finished(s))
        guard let callback else { return .none }
        return .callOnTermination(callback)
      }
    }

    @inlinable
    static func _upsertOnTermination(
      _ list: inout [(UInt64, @Sendable () -> Void)],
      sourceID: UInt64,
      callback: (@Sendable () -> Void)?
    ) {
      if let callback {
        if let idx = list.firstIndex(where: { $0.0 == sourceID }) {
          list[idx] = (sourceID, callback)
        } else {
          list.append((sourceID, callback))
        }
      } else {
        list.removeAll(where: { $0.0 == sourceID })
      }
    }

    @inlinable
    mutating func sourceInitialized() -> UInt64 {
      switch consume self._state {
      case .channeling(var s):
        let id = s.nextSourceID()
        self = .init(state: .channeling(s))
        return id
      case .sourceFinished(var s):
        let id = s.nextSourceID()
        self = .init(state: .sourceFinished(s))
        return id
      case .finished(let s):
        self = .init(state: .finished(s))
        return .max
      }
    }

    @usableFromInline
    enum ChannelDeinitializedAction: Sendable {
      case callOnTerminations([(UInt64, @Sendable () -> Void)])
      case failProducersAndCallOnTerminations(
        [_MultiProducerSingleConsumerSuspendedProducer],
        [(UInt64, @Sendable () -> Void)]
      )
    }

    @inlinable
    mutating func channelDeinitialized() -> ChannelDeinitializedAction? {
      switch consume self._state {
      case .channeling(let s):
        let producers = Array(s.suspendedProducers.lazy.map { $0.1 })
        let onTerminations = s.onTerminations
        self = .init(state: .finished(.init(sourceFinished: false)))
        return .failProducersAndCallOnTerminations(producers, onTerminations)

      case .sourceFinished(let s):
        let onTerminations = s.onTerminations
        self = .init(state: .finished(.init(sourceFinished: true)))
        return .callOnTerminations(onTerminations)

      case .finished(let s):
        self = .init(state: .finished(s))
        return .none
      }
    }

    @usableFromInline
    enum SendAction: ~Copyable, Sendable {
      case returnProduceMore
      case returnEnqueue(callbackToken: UInt64)
      case resumeReaderAndReturnProduceMore(
        continuation: UnsafeContinuation<Void, EitherError<Failure, CancellationError>>
      )
      case resumeReaderAndReturnEnqueue(
        continuation: UnsafeContinuation<Void, EitherError<Failure, CancellationError>>,
        callbackToken: UInt64
      )
      case throwFinishedError
    }

    @inlinable
    mutating func send(
      buffer: inout sending some RangeReplaceableContainer<Element> & ~Copyable
    ) -> sending SendAction {
      switch consume self._state {
      case .channeling(var s):
        // Take the noncopyable buffer out, drain the caller's buffer into it,
        // and put it back. We iterate elements via `consumeAll` so the caller
        // is left holding an empty buffer (per the writer contract).

        let shouldProduceMore: Bool = s.buffer.withValue {
          (inner: inout UniqueDeque<Element>?) -> Bool in
          // Take the deque out (or fabricate an empty one) so we can mutate
          // it without contending with the inout's exclusivity, then put it
          // back when we're done.
          var current: UniqueDeque<Element>
          if case .some(let taken) = inner.take() {
            current = taken
          } else {
            current = UniqueDeque<Element>()
          }
          let offsetBefore = current.count
          // Drain the caller's buffer into the channel's internal deque so
          // the caller is left holding an empty buffer (per the writer
          // contract). `consumeAll` iterates by-move and works for both
          // `Copyable` and `~Copyable` element types.
          var consumer = buffer.consumeAll()
          while let element = consumer.next() {
            current.append(element)
          }
          let didProduce = s.backpressureStrategy.didSend(
            buffer: current,
            appendedFromOffset: offsetBefore
          )
          inner = .some(current)
          return didProduce
        }
        s.hasOutstandingDemand = shouldProduceMore

        if let reader = s.readerContinuation.take() {
          let token = shouldProduceMore ? nil : s.nextCallbackToken()
          self = .init(state: .channeling(s))
          guard let token else {
            return .resumeReaderAndReturnProduceMore(continuation: reader)
          }
          return .resumeReaderAndReturnEnqueue(continuation: reader, callbackToken: token)
        }

        let token = shouldProduceMore ? nil : s.nextCallbackToken()
        self = .init(state: .channeling(s))
        guard let token else {
          return .returnProduceMore
        }
        return .returnEnqueue(callbackToken: token)

      case .sourceFinished(let s):
        self = .init(state: .sourceFinished(s))
        return .throwFinishedError

      case .finished(let s):
        self = .init(state: .finished(s))
        return .throwFinishedError
      }
    }

    @usableFromInline
    enum EnqueueProducerAction: ~Copyable, Sendable {
      case resumeProducer(_Disconnected<(Result<Void, any Error>) -> Void>)
      case resumeProducerWithError(_Disconnected<(Result<Void, any Error>) -> Void>, any Error)
    }

    @inlinable
    mutating func enqueueProducer(
      callbackToken: UInt64,
      onProduceMore: sending @escaping (Result<Void, any Error>) -> Void
    ) -> EnqueueProducerAction? {
      switch consume self._state {
      case .channeling(var s):
        if let idx = s.cancelledAsyncProducers.firstIndex(of: callbackToken) {
          s.cancelledAsyncProducers.remove(at: idx)
          self = .init(state: .channeling(s))
          return .resumeProducerWithError(.init(value: onProduceMore), CancellationError())
        }
        if s.hasOutstandingDemand {
          self = .init(state: .channeling(s))
          return .resumeProducer(.init(value: onProduceMore))
        }
        s.suspendedProducers.append((callbackToken, .closure(onProduceMore)))
        self = .init(state: .channeling(s))
        return .none

      case .sourceFinished(let s):
        self = .init(state: .sourceFinished(s))
        return .resumeProducerWithError(
          .init(value: onProduceMore),
          MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()
        )

      case .finished(let s):
        self = .init(state: .finished(s))
        return .resumeProducerWithError(
          .init(value: onProduceMore),
          MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()
        )
      }
    }

    @usableFromInline
    enum EnqueueContinuationAction: Sendable {
      case resumeProducer(UnsafeContinuation<Void, any Error>)
      case resumeProducerWithError(UnsafeContinuation<Void, any Error>, any Error)
    }

    @inlinable
    mutating func enqueueContinuation(
      callbackToken: UInt64,
      continuation: UnsafeContinuation<Void, any Error>
    ) -> EnqueueContinuationAction? {
      switch consume self._state {
      case .channeling(var s):
        if let idx = s.cancelledAsyncProducers.firstIndex(of: callbackToken) {
          s.cancelledAsyncProducers.remove(at: idx)
          self = .init(state: .channeling(s))
          return .resumeProducerWithError(continuation, CancellationError())
        }
        if s.hasOutstandingDemand {
          self = .init(state: .channeling(s))
          return .resumeProducer(continuation)
        }
        s.suspendedProducers.append((callbackToken, .continuation(continuation)))
        self = .init(state: .channeling(s))
        return .none

      case .sourceFinished(let s):
        self = .init(state: .sourceFinished(s))
        return .resumeProducerWithError(
          continuation,
          MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()
        )

      case .finished(let s):
        self = .init(state: .finished(s))
        return .resumeProducerWithError(
          continuation,
          MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()
        )
      }
    }

    @usableFromInline
    enum CancelProducerAction: Sendable {
      case resumeProducerWithCancellationError(_MultiProducerSingleConsumerSuspendedProducer)
    }

    @inlinable
    mutating func cancelProducer(callbackToken: UInt64) -> CancelProducerAction? {
      switch consume self._state {
      case .channeling(var s):
        guard let idx = s.suspendedProducers.firstIndex(where: { $0.0 == callbackToken }) else {
          s.cancelledAsyncProducers.append(callbackToken)
          self = .init(state: .channeling(s))
          return .none
        }
        let producer = s.suspendedProducers.remove(at: idx).1
        self = .init(state: .channeling(s))
        return .resumeProducerWithCancellationError(producer)

      case .sourceFinished(let s):
        self = .init(state: .sourceFinished(s))
        return .none

      case .finished(let s):
        self = .init(state: .finished(s))
        return .none
      }
    }

    @usableFromInline
    enum FinishAction: Sendable {
      case callOnTerminations([(UInt64, @Sendable () -> Void)])
      case resumeProducers([_MultiProducerSingleConsumerSuspendedProducer])
      case resumeReaderAndResumeProducers(
        UnsafeContinuation<Void, EitherError<Failure, CancellationError>>,
        [_MultiProducerSingleConsumerSuspendedProducer]
      )
    }

    @inlinable
    mutating func finish(failure: Failure?, finalElement: consuming sending FinalElement?) -> FinishAction? {
      switch consume self._state {
      case .channeling(var s):
        let reader = s.readerContinuation.take()
        let producers = Array(s.suspendedProducers.lazy.map { $0.1 })
        s.suspendedProducers.removeAll(keepingCapacity: false)

        self = .init(
          state: .sourceFinished(
            .init(
              buffer: _Disconnected(value: s.buffer.take()!),
              failure: failure,
              finalElement: _Disconnected(value: finalElement),
              onTerminations: s.onTerminations,
              nextSourceID: s._nextSourceID
            )
          )
        )

        if let reader {
          return .resumeReaderAndResumeProducers(reader, producers)
        }
        return .resumeProducers(producers)

      case .sourceFinished(let s):
        self = .init(state: .sourceFinished(s))
        return .none

      case .finished(let s):
        self = .init(state: .finished(s))
        return .none
      }
    }

    @usableFromInline
    enum ReadAvailableAction: ~Copyable, Sendable {
      case returnElements(_Disconnected<UniqueDeque<Element>>)
      case returnElementsAndResumeProducers(
        _Disconnected<UniqueDeque<Element>>,
        [_MultiProducerSingleConsumerSuspendedProducer]
      )
      case suspend
      /// Fused terminal chunk: deliver any remaining elements together with
      /// the optional `FinalElement` payload. The channel transitions to its
      /// finished state.
      case returnTerminalChunk(
        _Disconnected<UniqueDeque<Element>>,
        _Disconnected<FinalElement?>,
        [(UInt64, @Sendable () -> Void)]
      )
      /// The channel was finished with a failure and the buffer is now drained;
      /// throw the failure to the reader.
      case throwFailure(Failure?, [(UInt64, @Sendable () -> Void)])
      case returnNil
    }

    @inlinable
    mutating func readAvailable() -> ReadAvailableAction {
      switch consume self._state {
      case .channeling(var s):
        let isProducerBufferEmpty = s.buffer.withValue {
          $0.borrow()!.value.isEmpty
        }
        guard isProducerBufferEmpty else {
          // We are going to swap the two buffers around. The cached buffer
          // may not exist yet on the first read; fall back to a fresh empty
          // deque so the producer side always gets a valid container back.
          let readerBuffer = s.cachedReadBuffer.swap(newValue: nil) ?? UniqueDeque<Element>()
          let producerBuffer = s.buffer.swap(newValue: readerBuffer)!
          let shouldProduceMore = s.backpressureStrategy.didConsume(buffer: producerBuffer)
          s.hasOutstandingDemand = shouldProduceMore

          if shouldProduceMore && !s.suspendedProducers.isEmpty {
            let producers = Array(s.suspendedProducers.lazy.map { $0.1 })
            s.suspendedProducers.removeAll(keepingCapacity: true)
            self = .init(state: .channeling(s))
            return .returnElementsAndResumeProducers(
              _Disconnected(value: producerBuffer),
              producers
            )
          }
          self = .init(state: .channeling(s))
          return .returnElements(_Disconnected(value: producerBuffer))
        }
        self = .init(state: .channeling(s))
        return .suspend

      case .sourceFinished(var s):
        let buffer = s.buffer.swap(newValue: UniqueDeque<Element>())

        // Failure-path drains buffered elements first (without consuming the
        // failure), so the reader sees the trailing batch on one read and the
        // thrown failure on the next.
        if !buffer.isEmpty && s.failure != nil {
          // Leave s.buffer wrapping the now-empty placeholder.
          self = .init(state: .sourceFinished(s))
          nonisolated(unsafe) let bufferSending = consume buffer
          return .returnElements(_Disconnected(value: bufferSending))
        }

        // Otherwise fuse the (possibly empty) buffer with the optional
        // `FinalElement` and transition to finished.
        let fe = s.finalElement.swap(newValue: nil)
        let onTerminations = s.onTerminations
        let failure = s.failure
        self = .init(state: .finished(.init(sourceFinished: true)))

        if let failure {
          return .throwFailure(failure, onTerminations)
        }
        nonisolated(unsafe) let bufferSending = consume buffer
        nonisolated(unsafe) let feSending = consume fe
        return .returnTerminalChunk(
          _Disconnected(value: bufferSending),
          _Disconnected(value: feSending),
          onTerminations
        )

      case .finished(let s):
        self = .init(state: .finished(s))
        return .returnNil
      }
    }

    @inlinable
    mutating func returnCachedReadBuffer(_ buffer: consuming sending UniqueDeque<Element>) {
      var buffer = buffer
      switch consume self._state {
      case .channeling(var s):
        if !buffer.isEmpty {
          // The body did not consume every element. Re-add the leftover to
          // the watermark accounting (didConsume was already called for the
          // full handed-out batch in `readAvailable`), then prepend the
          // leftover to any newly-buffered producer writes so the next read
          // delivers them in order.
          _ = s.backpressureStrategy.didSend(buffer: buffer, appendedFromOffset: 0)
          s.buffer.withValue { (inner: inout UniqueDeque<Element>?) in
            var current: UniqueDeque<Element>
            if case .some(let taken) = inner.take() {
              current = taken
            } else {
              current = UniqueDeque<Element>()
            }
            while let last = buffer.popLast() {
              current.prepend(last)
            }
            inner = .some(current)
          }
        }
        // `buffer` is empty at this point; stash it for reuse on the next read.
        let _ = s.cachedReadBuffer.swap(newValue: buffer)
        self = .init(state: .channeling(s))

      case .sourceFinished(var s):
        if !buffer.isEmpty {
          // Preserve unconsumed elements at the head of the source-finished
          // buffer so the next read still sees them.
          var inner = s.buffer.swap(newValue: UniqueDeque<Element>())
          while let last = buffer.popLast() {
            inner.prepend(last)
          }
          nonisolated(unsafe) let innerSending = consume inner
          s.buffer = _Disconnected(value: innerSending)
        }
        self = .init(state: .sourceFinished(s))

      case .finished(let s):
        self = .init(state: .finished(s))
      }
    }

    @usableFromInline
    enum SuspendReadAction: ~Copyable, Sendable {
      case resumeReader(UnsafeContinuation<Void, EitherError<Failure, CancellationError>>)
    }

    @inlinable
    mutating func suspendRead(
      continuation: UnsafeContinuation<Void, EitherError<Failure, CancellationError>>
    ) -> SuspendReadAction? {
      switch consume self._state {
      case .channeling(var s):
        guard s.readerContinuation == nil else {
          fatalError("MultiProducerSingleConsumerAsyncChannel internal inconsistency: concurrent readers")
        }
        let isEmpty = s.buffer.withValue { $0.borrow()!.value.isEmpty }
        if !isEmpty {
          self = .init(state: .channeling(s))
          return .resumeReader(continuation)
        }
        s.readerContinuation = continuation
        self = .init(state: .channeling(s))
        return .none

      case .sourceFinished(let s):
        self = .init(state: .sourceFinished(s))
        return .resumeReader(continuation)

      case .finished(let s):
        self = .init(state: .finished(s))
        return .resumeReader(continuation)
      }
    }

    @usableFromInline
    enum CancelReadAction: Sendable {
      case resumeReaderWithCancellationError(
        UnsafeContinuation<Void, EitherError<Failure, CancellationError>>,
        [_MultiProducerSingleConsumerSuspendedProducer],
        [(UInt64, @Sendable () -> Void)]
      )
      case failProducersAndCallOnTerminations(
        [_MultiProducerSingleConsumerSuspendedProducer],
        [(UInt64, @Sendable () -> Void)]
      )
    }

    @inlinable
    mutating func cancelRead() -> CancelReadAction? {
      switch consume self._state {
      case .channeling(var s):
        let reader = s.readerContinuation.take()
        let producers = Array(s.suspendedProducers.lazy.map { $0.1 })
        let onTerminations = s.onTerminations
        self = .init(state: .finished(.init(sourceFinished: false)))
        if let reader {
          return .resumeReaderWithCancellationError(reader, producers, onTerminations)
        }
        return .failProducersAndCallOnTerminations(producers, onTerminations)

      case .sourceFinished(let s):
        self = .init(state: .sourceFinished(s))
        return .none

      case .finished(let s):
        self = .init(state: .finished(s))
        return .none
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel._Storage._StateMachine {
  @usableFromInline
  enum _State: ~Copyable, Sendable {
    @usableFromInline
    struct Channeling: ~Copyable, Sendable {
      @usableFromInline
      var backpressureStrategy: MultiProducerSingleConsumerAsyncChannel._InternalBackpressureStrategy

      @usableFromInline
      var onTerminations: [(UInt64, @Sendable () -> Void)] = []

      /// The buffer of elements pending consumption.
      @usableFromInline
      var buffer: _Disconnected<UniqueDeque<Element>?>

      /// A reusable empty buffer kept across reads to avoid per-read allocations.
      @usableFromInline
      var cachedReadBuffer: _Disconnected<UniqueDeque<Element>?>

      /// The continuation of a suspended ``read`` call.
      @usableFromInline
      var readerContinuation: UnsafeContinuation<Void, EitherError<Failure, CancellationError>>? = nil

      @usableFromInline
      var suspendedProducers: Deque<(UInt64, _MultiProducerSingleConsumerSuspendedProducer)>

      @usableFromInline
      var cancelledAsyncProducers: Deque<UInt64>

      @usableFromInline
      var hasOutstandingDemand: Bool

      @usableFromInline
      var nextCallbackTokenID: UInt64

      @usableFromInline
      var _nextSourceID: UInt64

      @inlinable
      init(
        backpressureStrategy: MultiProducerSingleConsumerAsyncChannel._InternalBackpressureStrategy,
        buffer: consuming _Disconnected<UniqueDeque<Element>?>,
        producerContinuations: Deque<(UInt64, _MultiProducerSingleConsumerSuspendedProducer)>,
        cancelledAsyncProducers: Deque<UInt64>,
        hasOutstandingDemand: Bool,
        nextCallbackTokenID: UInt64,
        nextSourceID: UInt64
      ) {
        self.backpressureStrategy = backpressureStrategy
        self.buffer = buffer
        self.cachedReadBuffer = _Disconnected(value: nil)
        self.suspendedProducers = producerContinuations
        self.cancelledAsyncProducers = cancelledAsyncProducers
        self.hasOutstandingDemand = hasOutstandingDemand
        self.nextCallbackTokenID = nextCallbackTokenID
        self._nextSourceID = nextSourceID
      }

      @inlinable
      mutating func nextCallbackToken() -> UInt64 {
        defer { self.nextCallbackTokenID += 1 }
        return self.nextCallbackTokenID
      }

      @inlinable
      mutating func nextSourceID() -> UInt64 {
        defer { self._nextSourceID += 1 }
        return self._nextSourceID
      }
    }

    @usableFromInline
    struct SourceFinished: ~Copyable, Sendable {
      @usableFromInline
      var buffer: _Disconnected<UniqueDeque<Element>>

      @usableFromInline
      var failure: Failure?

      @usableFromInline
      var finalElement: _Disconnected<FinalElement?>

      @usableFromInline
      var onTerminations: [(UInt64, @Sendable () -> Void)]

      @usableFromInline
      var _nextSourceID: UInt64

      @inlinable
      init(
        buffer: consuming _Disconnected<UniqueDeque<Element>>,
        failure: Failure? = nil,
        finalElement: consuming _Disconnected<FinalElement?> = .init(value: nil),
        onTerminations: [(UInt64, @Sendable () -> Void)] = [],
        nextSourceID: UInt64
      ) {
        self.buffer = buffer
        self.failure = failure
        self.finalElement = finalElement
        self.onTerminations = onTerminations
        self._nextSourceID = nextSourceID
      }

      @inlinable
      mutating func nextSourceID() -> UInt64 {
        defer { self._nextSourceID += 1 }
        return self._nextSourceID
      }
    }

    @usableFromInline
    struct Finished: ~Copyable, Sendable {
      @usableFromInline
      var sourceFinished: Bool

      @inlinable
      init(sourceFinished: Bool) { self.sourceFinished = sourceFinished }
    }

    case channeling(Channeling)
    case sourceFinished(SourceFinished)
    case finished(Finished)
  }
}

/// A producer suspended waiting for backpressure to allow further sends.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
@usableFromInline
enum _MultiProducerSingleConsumerSuspendedProducer: @unchecked Sendable {
  case closure((Result<Void, any Error>) -> Void)
  case continuation(UnsafeContinuation<Void, any Error>)
}

/// Helper to move a non-Sendable value across isolation regions (mirror of
/// the helper in AsyncAlgorithms; kept private to AsyncStreaming to avoid
/// reaching into another module's internals).
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
@usableFromInline
struct _Disconnected<Value: ~Copyable>: ~Copyable, Sendable {
  private nonisolated(unsafe) var value: Value

  @usableFromInline
  init(value: consuming sending Value) {
    self.value = value
  }

  @usableFromInline
  consuming func take() -> sending Value {
    let value = consume value
    return value
  }

  @discardableResult
  @usableFromInline
  mutating func swap(newValue: consuming sending Value) -> sending Value {
    let value = consume value
    self = _Disconnected(value: newValue)
    return value
  }

  @usableFromInline
  mutating func withValue<Return: ~Copyable, Failure>(
    body: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    var value = consume value
    let result: Return
    do throws(Failure) {
      result = try body(&value)
    } catch {
      self = _Disconnected(value: value)
      throw error
    }
    self = _Disconnected(value: value)
    return result
  }
}
#endif

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

import DequeModule

struct _AsyncBackPressuredStreamWatermarkBackPressureStrategy<Element> {
    /// The low watermark where demand should start.
    private let low: Int
    /// The high watermark where demand should be stopped.
    private let high: Int
    private var currentWatermark: Int = 0
    private let waterLevelForElement: (@Sendable (Element) -> Int)?

    /// Initializes a new ``_WatermarkBackPressureStrategy``.
    ///
    /// - Parameters:
    ///   - low: The low watermark where demand should start.
    ///   - high: The high watermark where demand should be stopped.
    init(low: Int, high: Int, waterLevelForElement: (@Sendable (Element) -> Int)?) {
        precondition(low <= high)
        self.low = low
        self.high = high
        self.waterLevelForElement = waterLevelForElement
    }

    mutating func didYield(elements: Deque<Element>.SubSequence) -> Bool {
        if let waterLevelForElement {
            self.currentWatermark += elements.reduce(0) { $0 + waterLevelForElement($1) }
        } else {
            self.currentWatermark += elements.count
        }
        precondition(self.currentWatermark >= 0)
        // We are demanding more until we reach the high watermark
        return self.currentWatermark < self.high
    }

    mutating func didConsume(element: Element) -> Bool {
        if let waterLevelForElement {
            self.currentWatermark -= waterLevelForElement(element)
        } else {
            self.currentWatermark -= 1
        }
        precondition(self.currentWatermark >= 0)
        // We start demanding again once we are below the low watermark
        return self.currentWatermark < self.low
    }
}

enum _AsyncBackPressuredStreamInternalBackPressureStrategy<Element> {
    case watermark(_AsyncBackPressuredStreamWatermarkBackPressureStrategy<Element>)

    mutating func didYield(elements: Deque<Element>.SubSequence) -> Bool {
        switch self {
        case .watermark(var strategy):
            let result = strategy.didYield(elements: elements)
            self = .watermark(strategy)
            return result
        }
    }

    mutating func didConsume(element: Element) -> Bool {
        switch self {
        case .watermark(var strategy):
            let result = strategy.didConsume(element: element)
            self = .watermark(strategy)
            return result
        }
    }
}

// We are unchecked Sendable since we are protecting our state with a lock.
final class _AsyncBackPressuredStreamBackPressuredStorage<Element, Failure: Error>: @unchecked Sendable {
    /// The state machine
    var _stateMachine: ManagedCriticalState<_AsyncBackPressuredStateMachine<Element, Failure>>

    var onTermination: (@Sendable () -> Void)? {
        set {
            self._stateMachine.withCriticalRegion {
                $0._onTermination = newValue
            }
        }
        get {
            self._stateMachine.withCriticalRegion {
                $0._onTermination
            }
        }
    }

    init(
        backPressureStrategy: _AsyncBackPressuredStreamInternalBackPressureStrategy<Element>
    ) {
        self._stateMachine = .init(.init(backPressureStrategy: backPressureStrategy))
    }

    func sequenceDeinitialized() {
        let action = self._stateMachine.withCriticalRegion {
            $0.sequenceDeinitialized()
        }

        switch action {
        case .callOnTermination(let onTermination):
            onTermination?()

        case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
            for producerContinuation in producerContinuations {
                producerContinuation(.failure(AsyncBackPressuredStreamAlreadyFinishedError()))
            }
            onTermination?()

        case .none:
            break
        }
    }

    func iteratorInitialized() {
        self._stateMachine.withCriticalRegion {
            $0.iteratorInitialized()
        }
    }

    func iteratorDeinitialized() {
        let action = self._stateMachine.withCriticalRegion {
            $0.iteratorDeinitialized()
        }

        switch action {
        case .callOnTermination(let onTermination):
            onTermination?()

        case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
            for producerContinuation in producerContinuations {
                producerContinuation(.failure(AsyncBackPressuredStreamAlreadyFinishedError()))
            }
            onTermination?()

        case .none:
            break
        }
    }

    func sourceDeinitialized() {
        let action = self._stateMachine.withCriticalRegion {
            $0.sourceDeinitialized()
        }

        switch action {
        case .callOnTermination(let onTermination):
            onTermination?()

        case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
            for producerContinuation in producerContinuations {
                producerContinuation(.failure(AsyncBackPressuredStreamAlreadyFinishedError()))
            }
            onTermination?()

        case .failProducers(let producerContinuations):
            for producerContinuation in producerContinuations {
                producerContinuation(.failure(AsyncBackPressuredStreamAlreadyFinishedError()))
            }

        case .none:
            break
        }
    }

    func write(
        contentsOf sequence: some Sequence<Element>
    ) throws -> AsyncBackPressuredStream<Element, Failure>.Source.WriteResult {
        let action = self._stateMachine.withCriticalRegion {
            return $0.write(sequence)
        }

        switch action {
        case .returnProduceMore:
            return .produceMore

        case .returnEnqueue(let callbackToken):
            return .enqueueCallback(callbackToken)

        case .resumeConsumerAndReturnProduceMore(let continuation, let element):
            continuation.resume(returning: element)
            return .produceMore

        case .resumeConsumerAndReturnEnqueue(let continuation, let element, let callbackToken):
            continuation.resume(returning: element)
            return .enqueueCallback(callbackToken)

        case .throwFinishedError:
            throw AsyncBackPressuredStreamAlreadyFinishedError()
        }
    }

    func enqueueProducer(
        callbackToken: AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken,
        onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let action = self._stateMachine.withCriticalRegion {
            $0.enqueueProducer(callbackToken: callbackToken, onProduceMore: onProduceMore)
        }

        switch action {
        case .resumeProducer(let onProduceMore):
            onProduceMore(Result<Void, Error>.success(()))

        case .resumeProducerWithError(let onProduceMore, let error):
            onProduceMore(Result<Void, Error>.failure(error))

        case .none:
            break
        }
    }

    func cancelProducer(
        callbackToken: AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken
    ) {
        let action = self._stateMachine.withCriticalRegion {
            $0.cancelProducer(callbackToken: callbackToken)
        }

        switch action {
        case .resumeProducerWithCancellationError(let onProduceMore):
            onProduceMore(Result<Void, Error>.failure(CancellationError()))

        case .none:
            break
        }
    }

    func finish(_ failure: Failure?) {
        let action = self._stateMachine.withCriticalRegion {
            $0.finish(failure)
        }

        switch action {
        case .callOnTermination(let onTermination):
            onTermination?()

        case .resumeConsumerAndCallOnTermination(let consumerContinuation, let failure, let onTermination):
            switch failure {
            case .some(let error):
                consumerContinuation.resume(throwing: error)
            case .none:
                consumerContinuation.resume(returning: nil)
            }

            onTermination?()

        case .resumeProducers(let producerContinuations):
            for producerContinuation in producerContinuations {
                producerContinuation(.failure(AsyncBackPressuredStreamAlreadyFinishedError()))
            }

        case .none:
            break
        }
    }

    func next() async throws -> Element? {
        let action = self._stateMachine.withCriticalRegion {
            $0.next()
        }

        switch action {
        case .returnElement(let element):
            return element

        case .returnElementAndResumeProducers(let element, let producerContinuations):
            for producerContinuation in producerContinuations {
                producerContinuation(Result<Void, Error>.success(()))
            }

            return element

        case .returnFailureAndCallOnTermination(let failure, let onTermination):
            onTermination?()
            switch failure {
            case .some(let error):
                throw error

            case .none:
                return nil
            }

        case .returnNil:
            return nil

        case .suspendTask:
            return try await self.suspendNext()
        }
    }

    func suspendNext() async throws -> Element? {
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let action = self._stateMachine.withCriticalRegion {
                    $0.suspendNext(continuation: continuation)
                }

                switch action {
                case .resumeConsumerWithElement(let continuation, let element):
                    continuation.resume(returning: element)

                case .resumeConsumerWithElementAndProducers(let continuation, let element, let producerContinuations):
                    continuation.resume(returning: element)
                    for producerContinuation in producerContinuations {
                        producerContinuation(Result<Void, Error>.success(()))
                    }

                case .resumeConsumerWithFailureAndCallOnTermination(let continuation, let failure, let onTermination):
                    switch failure {
                    case .some(let error):
                        continuation.resume(throwing: error)

                    case .none:
                        continuation.resume(returning: nil)
                    }
                    onTermination?()

                case .resumeConsumerWithNil(let continuation):
                    continuation.resume(returning: nil)

                case .none:
                    break
                }
            }
        } onCancel: {
            let action = self._stateMachine.withCriticalRegion {
                $0.cancelNext()
            }

            switch action {
            case .resumeConsumerWithNilAndCallOnTermination(let continuation, let onTermination):
                continuation.resume(returning: nil)
                onTermination?()

            case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
                for producerContinuation in producerContinuations {
                    producerContinuation(.failure(AsyncBackPressuredStreamAlreadyFinishedError()))
                }
                onTermination?()

            case .none:
                break
            }
        }
    }
}

/// The state machine of the backpressured async stream.
struct _AsyncBackPressuredStateMachine<Element, Failure: Error>: Sendable {
    enum _State {
        struct Initial {
            /// The backpressure strategy.
            var backPressureStrategy: _AsyncBackPressuredStreamInternalBackPressureStrategy<Element>
            /// Indicates if the iterator was initialized.
            var iteratorInitialized: Bool
            /// The onTermination callback.
            var onTermination: (@Sendable () -> Void)?
        }

        struct Streaming {
            /// The backpressure strategy.
            var backPressureStrategy: _AsyncBackPressuredStreamInternalBackPressureStrategy<Element>
            /// Indicates if the iterator was initialized.
            var iteratorInitialized: Bool
            /// The onTermination callback.
            var onTermination: (@Sendable () -> Void)?
            /// The buffer of elements.
            var buffer: Deque<Element>
            /// The optional consumer continuation.
            var consumerContinuation: CheckedContinuation<Element?, Error>?
            /// The producer continuations.
            var producerContinuations: Deque<(UInt, (Result<Void, Error>) -> Void)>
            /// The producers that have been cancelled.
            var cancelledAsyncProducers: Deque<UInt>
            /// Indicates if we currently have outstanding demand.
            var hasOutstandingDemand: Bool
        }

        struct SourceFinished {
            /// Indicates if the iterator was initialized.
            var iteratorInitialized: Bool
            /// The buffer of elements.
            var buffer: Deque<Element>
            /// The failure that should be thrown after the last element has been consumed.
            var failure: Failure?
            /// The onTermination callback.
            var onTermination: (@Sendable () -> Void)?
        }

        case initial(Initial)
        /// The state once either any element was yielded or `next()` was called.
        case streaming(Streaming)
        /// The state once the underlying source signalled that it is finished.
        case sourceFinished(SourceFinished)

        /// The state once there can be no outstanding demand. This can happen if:
        /// 1. The iterator was deinited
        /// 2. The underlying source finished and all buffered elements have been consumed
        case finished(iteratorInitialized: Bool)

        /// An intermediate state to avoid CoWs.
        case modify
    }

    /// The state machine's current state.
    var _state: _State

    // The ID used for the next CallbackToken.
    var nextCallbackTokenID: UInt = 0

    var _onTermination: (@Sendable () -> Void)? {
        set {
            switch self._state {
            case .initial(var initial):
                initial.onTermination = newValue
                self._state = .initial(initial)

            case .streaming(var streaming):
                streaming.onTermination = newValue
                self._state = .streaming(streaming)

            case .sourceFinished(var sourceFinished):
                sourceFinished.onTermination = newValue
                self._state = .sourceFinished(sourceFinished)

            case .finished:
                break

            case .modify:
                fatalError("AsyncStream internal inconsistency")
            }
        }
        get {
            switch self._state {
            case .initial(let initial):
                return initial.onTermination

            case .streaming(let streaming):
                return streaming.onTermination

            case .sourceFinished(let sourceFinished):
                return sourceFinished.onTermination

            case .finished:
                return nil

            case .modify:
                fatalError("AsyncStream internal inconsistency")
            }
        }
    }

    /// Initializes a new `StateMachine`.
    ///
    /// We are passing and holding the back-pressure strategy here because
    /// it is a customizable extension of the state machine.
    ///
    /// - Parameter backPressureStrategy: The back-pressure strategy.
    init(
        backPressureStrategy: _AsyncBackPressuredStreamInternalBackPressureStrategy<Element>
    ) {
        self._state = .initial(
            .init(
                backPressureStrategy: backPressureStrategy,
                iteratorInitialized: false,
                onTermination: nil
            )
        )
    }

    /// Generates the next callback token.
    mutating func nextCallbackToken() -> AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken {
        let id = self.nextCallbackTokenID
        self.nextCallbackTokenID += 1
        return .init(id: id)
    }

    /// Actions returned by `sequenceDeinitialized()`.
    enum SequenceDeinitializedAction {
        /// Indicates that `onTermination` should be called.
        case callOnTermination((@Sendable () -> Void)?)
        /// Indicates that  all producers should be failed and `onTermination` should be called.
        case failProducersAndCallOnTermination(
            [(Result<Void, Error>) -> Void],
            (@Sendable () -> Void)?
        )
    }

    mutating func sequenceDeinitialized() -> SequenceDeinitializedAction? {
        switch self._state {
        case .initial(let initial):
            guard initial.iteratorInitialized else {
                // No iterator was created so we can transition to finished right away.
                self._state = .finished(iteratorInitialized: false)

                return .callOnTermination(initial.onTermination)
            }
            // An iterator was created and we deinited the sequence.
            // This is an expected pattern and we just continue on normal.
            return .none

        case .streaming(let streaming):
            guard streaming.iteratorInitialized else {
                // No iterator was created so we can transition to finished right away.
                self._state = .finished(iteratorInitialized: false)

                return .failProducersAndCallOnTermination(
                    Array(streaming.producerContinuations.map { $0.1 }),
                    streaming.onTermination
                )
            }
            // An iterator was created and we deinited the sequence.
            // This is an expected pattern and we just continue on normal.
            return .none

        case .sourceFinished(let sourceFinished):
            guard sourceFinished.iteratorInitialized else {
                // No iterator was created so we can transition to finished right away.
                self._state = .finished(iteratorInitialized: false)

                return .callOnTermination(sourceFinished.onTermination)
            }
            // An iterator was created and we deinited the sequence.
            // This is an expected pattern and we just continue on normal.
            return .none

        case .finished:
            // We are already finished so there is nothing left to clean up.
            // This is just the references dropping afterwards.
            return .none

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    mutating func iteratorInitialized() {
        switch self._state {
        case .initial(var initial):
            if initial.iteratorInitialized {
                // Our sequence is a unicast sequence and does not support multiple AsyncIterator's
                fatalError("Only a single AsyncIterator can be created")
            } else {
                // The first and only iterator was initialized.
                initial.iteratorInitialized = true
                self._state = .initial(initial)
            }

        case .streaming(var streaming):
            if streaming.iteratorInitialized {
                // Our sequence is a unicast sequence and does not support multiple AsyncIterator's
                fatalError("Only a single AsyncIterator can be created")
            } else {
                // The first and only iterator was initialized.
                streaming.iteratorInitialized = true
                self._state = .streaming(streaming)
            }

        case .sourceFinished(var sourceFinished):
            if sourceFinished.iteratorInitialized {
                // Our sequence is a unicast sequence and does not support multiple AsyncIterator's
                fatalError("Only a single AsyncIterator can be created")
            } else {
                // The first and only iterator was initialized.
                sourceFinished.iteratorInitialized = true
                self._state = .sourceFinished(sourceFinished)
            }

        case .finished(iteratorInitialized: true):
            // Our sequence is a unicast sequence and does not support multiple AsyncIterator's
            fatalError("Only a single AsyncIterator can be created")

        case .finished(iteratorInitialized: false):
            // It is strange that an iterator is created after we are finished
            // but it can definitely happen, e.g.
            // Sequence.init -> source.finish -> sequence.makeAsyncIterator
            self._state = .finished(iteratorInitialized: true)

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `iteratorDeinitialized()`.
    enum IteratorDeinitializedAction {
        /// Indicates that `onTermination` should be called.
        case callOnTermination((@Sendable () -> Void)?)
        /// Indicates that  all producers should be failed and `onTermination` should be called.
        case failProducersAndCallOnTermination(
            [(Result<Void, Error>) -> Void],
            (@Sendable () -> Void)?
        )
    }

    mutating func iteratorDeinitialized() -> IteratorDeinitializedAction? {
        switch self._state {
        case .initial(let initial):
            if initial.iteratorInitialized {
                // An iterator was created and deinited. Since we only support
                // a single iterator we can now transition to finish.
                self._state = .finished(iteratorInitialized: true)
                return .callOnTermination(initial.onTermination)
            } else {
                // An iterator needs to be initialized before it can be deinitialized.
                fatalError("AsyncStream internal inconsistency")
            }

        case .streaming(let streaming):
            if streaming.iteratorInitialized {
                // An iterator was created and deinited. Since we only support
                // a single iterator we can now transition to finish.
                self._state = .finished(iteratorInitialized: true)

                return .failProducersAndCallOnTermination(
                    Array(streaming.producerContinuations.map { $0.1 }),
                    streaming.onTermination
                )
            } else {
                // An iterator needs to be initialized before it can be deinitialized.
                fatalError("AsyncStream internal inconsistency")
            }

        case .sourceFinished(let sourceFinished):
            if sourceFinished.iteratorInitialized {
                // An iterator was created and deinited. Since we only support
                // a single iterator we can now transition to finish.
                self._state = .finished(iteratorInitialized: true)
                return .callOnTermination(sourceFinished.onTermination)
            } else {
                // An iterator needs to be initialized before it can be deinitialized.
                fatalError("AsyncStream internal inconsistency")
            }

        case .finished:
            // We are already finished so there is nothing left to clean up.
            // This is just the references dropping afterwards.
            return .none

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `sourceDeinitialized()`.
    enum SourceDeinitializedAction {
        /// Indicates that `onTermination` should be called.
        case callOnTermination((() -> Void)?)
        /// Indicates that  all producers should be failed and `onTermination` should be called.
        case failProducersAndCallOnTermination(
            [(Result<Void, Error>) -> Void],
            (@Sendable () -> Void)?
        )
        /// Indicates that all producers should be failed.
        case failProducers([(Result<Void, Error>) -> Void])
    }

    mutating func sourceDeinitialized() -> SourceDeinitializedAction? {
        switch self._state {
        case .initial(let initial):
            // The source got deinited before anything was written
            self._state = .finished(iteratorInitialized: initial.iteratorInitialized)
            return .callOnTermination(initial.onTermination)

        case .streaming(let streaming):
            guard streaming.buffer.isEmpty else {
                // The continuation must be `nil` if the buffer has elements
                precondition(streaming.consumerContinuation == nil)

                self._state = .sourceFinished(
                    .init(
                        iteratorInitialized: streaming.iteratorInitialized,
                        buffer: streaming.buffer,
                        failure: nil,
                        onTermination: streaming.onTermination
                    )
                )

                return .failProducers(
                    Array(streaming.producerContinuations.map { $0.1 })
                )
            }
            // We can transition to finished right away since the buffer is empty now
            self._state = .finished(iteratorInitialized: streaming.iteratorInitialized)

            return .failProducersAndCallOnTermination(
                Array(streaming.producerContinuations.map { $0.1 }),
                streaming.onTermination
            )

        case .sourceFinished, .finished:
            // This is normal and we just have to tolerate it
            return .none

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `write()`.
    enum WriteAction {
        /// Indicates that the producer should be notified to produce more.
        case returnProduceMore
        /// Indicates that the producer should be suspended to stop producing.
        case returnEnqueue(
            callbackToken: AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken
        )
        /// Indicates that the consumer should be resumed and the producer should be notified to produce more.
        case resumeConsumerAndReturnProduceMore(
            continuation: CheckedContinuation<Element?, Error>,
            element: Element
        )
        /// Indicates that the consumer should be resumed and the producer should be suspended.
        case resumeConsumerAndReturnEnqueue(
            continuation: CheckedContinuation<Element?, Error>,
            element: Element,
            callbackToken: AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken
        )
        /// Indicates that the producer has been finished.
        case throwFinishedError

        init(
            callbackToken: AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken?,
            continuationAndElement: (CheckedContinuation<Element?, Error>, Element)? = nil
        ) {
            switch (callbackToken, continuationAndElement) {
            case (.none, .none):
                self = .returnProduceMore

            case (.some(let callbackToken), .none):
                self = .returnEnqueue(callbackToken: callbackToken)

            case (.none, .some((let continuation, let element))):
                self = .resumeConsumerAndReturnProduceMore(
                    continuation: continuation,
                    element: element
                )

            case (.some(let callbackToken), .some((let continuation, let element))):
                self = .resumeConsumerAndReturnEnqueue(
                    continuation: continuation,
                    element: element,
                    callbackToken: callbackToken
                )
            }
        }
    }

    mutating func write(_ sequence: some Sequence<Element>) -> WriteAction {
        switch self._state {
        case .initial(var initial):
            var buffer = Deque<Element>()
            buffer.append(contentsOf: sequence)

            let shouldProduceMore = initial.backPressureStrategy.didYield(elements: buffer[...])
            let callbackToken = shouldProduceMore ? nil : self.nextCallbackToken()

            self._state = .streaming(
                .init(
                    backPressureStrategy: initial.backPressureStrategy,
                    iteratorInitialized: initial.iteratorInitialized,
                    onTermination: initial.onTermination,
                    buffer: buffer,
                    consumerContinuation: nil,
                    producerContinuations: .init(),
                    cancelledAsyncProducers: .init(),
                    hasOutstandingDemand: shouldProduceMore
                )
            )

            return .init(callbackToken: callbackToken)

        case .streaming(var streaming):
            self._state = .modify

            // We have an element and can resume the continuation
            let bufferEndIndexBeforeAppend = streaming.buffer.endIndex
            streaming.buffer.append(contentsOf: sequence)
            let shouldProduceMore = streaming.backPressureStrategy.didYield(
                elements: streaming.buffer[bufferEndIndexBeforeAppend...]
            )
            streaming.hasOutstandingDemand = shouldProduceMore
            let callbackToken = shouldProduceMore ? nil : self.nextCallbackToken()

            guard let consumerContinuation = streaming.consumerContinuation else {
                // We don't have a suspended consumer so we just buffer the elements
                self._state = .streaming(streaming)
                return .init(
                    callbackToken: callbackToken
                )
            }
            guard let element = streaming.buffer.popFirst() else {
                // We got a yield of an empty sequence. We just tolerate this.
                self._state = .streaming(streaming)

                return .init(callbackToken: callbackToken)
            }

            // We got a consumer continuation and an element. We can resume the consumer now
            streaming.consumerContinuation = nil
            self._state = .streaming(streaming)
            return .init(
                callbackToken: callbackToken,
                continuationAndElement: (consumerContinuation, element)
            )

        case .sourceFinished, .finished:
            // If the source has finished we are dropping the elements.
            return .throwFinishedError

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `enqueueProducer()`.
    enum EnqueueProducerAction {
        /// Indicates that the producer should be notified to produce more.
        case resumeProducer((Result<Void, Error>) -> Void)
        /// Indicates that the producer should be notified about an error.
        case resumeProducerWithError((Result<Void, Error>) -> Void, Error)
    }

    mutating func enqueueProducer(
        callbackToken: AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken,
        onProduceMore: @Sendable @escaping (Result<Void, Error>) -> Void
    ) -> EnqueueProducerAction? {
        switch self._state {
        case .initial:
            // We need to transition to streaming before we can suspend
            // This is enforced because the CallbackToken has no public init so
            // one must create it by calling `write` first.
            fatalError("AsyncStream internal inconsistency")

        case .streaming(var streaming):
            if let index = streaming.cancelledAsyncProducers.firstIndex(of: callbackToken.id) {
                // Our producer got marked as cancelled.
                self._state = .modify
                streaming.cancelledAsyncProducers.remove(at: index)
                self._state = .streaming(streaming)

                return .resumeProducerWithError(onProduceMore, CancellationError())
            } else if streaming.hasOutstandingDemand {
                // We hit an edge case here where we wrote but the consuming thread got interleaved
                return .resumeProducer(onProduceMore)
            } else {
                self._state = .modify
                streaming.producerContinuations.append((callbackToken.id, onProduceMore))

                self._state = .streaming(streaming)
                return .none
            }

        case .sourceFinished, .finished:
            // Since we are unlocking between yielding and suspending the yield
            // It can happen that the source got finished or the consumption fully finishes.
            return .resumeProducerWithError(onProduceMore, AsyncBackPressuredStreamAlreadyFinishedError())

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `cancelProducer()`.
    enum CancelProducerAction {
        /// Indicates that the producer should be notified about cancellation.
        case resumeProducerWithCancellationError((Result<Void, Error>) -> Void)
    }

    mutating func cancelProducer(
        callbackToken: AsyncBackPressuredStream<Element, Failure>.Source.WriteResult.CallbackToken
    ) -> CancelProducerAction? {
        switch self._state {
        case .initial:
            // We need to transition to streaming before we can suspend
            fatalError("AsyncStream internal inconsistency")

        case .streaming(var streaming):
            guard let index = streaming.producerContinuations.firstIndex(where: { $0.0 == callbackToken.id }) else {
                // The task that yields was cancelled before yielding so the cancellation handler
                // got invoked right away
                self._state = .modify
                streaming.cancelledAsyncProducers.append(callbackToken.id)
                self._state = .streaming(streaming)

                return .none
            }
            // We have an enqueued producer that we need to resume now
            self._state = .modify
            let continuation = streaming.producerContinuations.remove(at: index).1
            self._state = .streaming(streaming)

            return .resumeProducerWithCancellationError(continuation)

        case .sourceFinished, .finished:
            // Since we are unlocking between yielding and suspending the yield
            // It can happen that the source got finished or the consumption fully finishes.
            return .none

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `finish()`.
    enum FinishAction {
        /// Indicates that `onTermination` should be called.
        case callOnTermination((() -> Void)?)
        /// Indicates that the consumer  should be resumed with the failure, the producers
        /// should be resumed with an error and `onTermination` should be called.
        case resumeConsumerAndCallOnTermination(
            consumerContinuation: CheckedContinuation<Element?, Error>,
            failure: Failure?,
            onTermination: (() -> Void)?
        )
        /// Indicates that the producers should be resumed with an error.
        case resumeProducers(
            producerContinuations: [(Result<Void, Error>) -> Void]
        )
    }

    @inlinable
    mutating func finish(_ failure: Failure?) -> FinishAction? {
        switch self._state {
        case .initial(let initial):
            // Nothing was yielded nor did anybody call next
            // This means we can transition to sourceFinished and store the failure
            self._state = .sourceFinished(
                .init(
                    iteratorInitialized: initial.iteratorInitialized,
                    buffer: .init(),
                    failure: failure,
                    onTermination: initial.onTermination
                )
            )

            return .callOnTermination(initial.onTermination)

        case .streaming(let streaming):
            guard let consumerContinuation = streaming.consumerContinuation else {
                self._state = .sourceFinished(
                    .init(
                        iteratorInitialized: streaming.iteratorInitialized,
                        buffer: streaming.buffer,
                        failure: failure,
                        onTermination: streaming.onTermination
                    )
                )

                return .resumeProducers(producerContinuations: Array(streaming.producerContinuations.map { $0.1 }))
            }
            // We have a continuation, this means our buffer must be empty
            // Furthermore, we can now transition to finished
            // and resume the continuation with the failure
            precondition(streaming.buffer.isEmpty, "Expected an empty buffer")
            precondition(streaming.producerContinuations.isEmpty, "Expected no suspended producers")

            self._state = .finished(iteratorInitialized: streaming.iteratorInitialized)

            return .resumeConsumerAndCallOnTermination(
                consumerContinuation: consumerContinuation,
                failure: failure,
                onTermination: streaming.onTermination
            )

        case .sourceFinished, .finished:
            // If the source has finished, finishing again has no effect.
            return .none

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `next()`.
    enum NextAction {
        /// Indicates that the element should be returned to the caller.
        case returnElement(Element)
        /// Indicates that the element should be returned to the caller and that all producers should be called.
        case returnElementAndResumeProducers(Element, [(Result<Void, Error>) -> Void])
        /// Indicates that the `Failure` should be returned to the caller and that `onTermination` should be called.
        case returnFailureAndCallOnTermination(Failure?, (() -> Void)?)
        /// Indicates that the `nil` should be returned to the caller.
        case returnNil
        /// Indicates that the `Task` of the caller should be suspended.
        case suspendTask
    }

    mutating func next() -> NextAction {
        switch self._state {
        case .initial(let initial):
            // We are not interacting with the back-pressure strategy here because
            // we are doing this inside `next(:)`
            self._state = .streaming(
                .init(
                    backPressureStrategy: initial.backPressureStrategy,
                    iteratorInitialized: initial.iteratorInitialized,
                    onTermination: initial.onTermination,
                    buffer: Deque<Element>(),
                    consumerContinuation: nil,
                    producerContinuations: .init(),
                    cancelledAsyncProducers: .init(),
                    hasOutstandingDemand: false
                )
            )

            return .suspendTask
        case .streaming(var streaming):
            guard streaming.consumerContinuation == nil else {
                // We have multiple AsyncIterators iterating the sequence
                fatalError("AsyncStream internal inconsistency")
            }

            self._state = .modify

            guard let element = streaming.buffer.popFirst() else {
                // There is nothing in the buffer to fulfil the demand so we need to suspend.
                // We are not interacting with the back-pressure strategy here because
                // we are doing this inside `suspendNext`
                self._state = .streaming(streaming)

                return .suspendTask
            }
            // We have an element to fulfil the demand right away.
            let shouldProduceMore = streaming.backPressureStrategy.didConsume(element: element)
            streaming.hasOutstandingDemand = shouldProduceMore

            guard shouldProduceMore else {
                // We don't have any new demand, so we can just return the element.
                self._state = .streaming(streaming)
                return .returnElement(element)
            }
            // There is demand and we have to resume our producers
            let producers = Array(streaming.producerContinuations.map { $0.1 })
            streaming.producerContinuations.removeAll()
            self._state = .streaming(streaming)
            return .returnElementAndResumeProducers(element, producers)

        case .sourceFinished(var sourceFinished):
            // Check if we have an element left in the buffer and return it
            self._state = .modify

            guard let element = sourceFinished.buffer.popFirst() else {
                // We are returning the queued failure now and can transition to finished
                self._state = .finished(iteratorInitialized: sourceFinished.iteratorInitialized)

                return .returnFailureAndCallOnTermination(sourceFinished.failure, sourceFinished.onTermination)
            }
            self._state = .sourceFinished(sourceFinished)

            return .returnElement(element)

        case .finished:
            return .returnNil

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `suspendNext()`.
    enum SuspendNextAction {
        /// Indicates that the consumer should be resumed.
        case resumeConsumerWithElement(CheckedContinuation<Element?, Error>, Element)
        /// Indicates that the consumer and all producers should be resumed.
        case resumeConsumerWithElementAndProducers(
            CheckedContinuation<Element?, Error>,
            Element,
            [(Result<Void, Error>) -> Void]
        )
        /// Indicates that the consumer should be resumed with the failure and that `onTermination` should be called.
        case resumeConsumerWithFailureAndCallOnTermination(
            CheckedContinuation<Element?, Error>,
            Failure?,
            (() -> Void)?
        )
        /// Indicates that the consumer should be resumed with `nil`.
        case resumeConsumerWithNil(CheckedContinuation<Element?, Error>)
    }

    mutating func suspendNext(continuation: CheckedContinuation<Element?, Error>) -> SuspendNextAction? {
        switch self._state {
        case .initial:
            // We need to transition to streaming before we can suspend
            preconditionFailure("AsyncStream internal inconsistency")

        case .streaming(var streaming):
            guard streaming.consumerContinuation == nil else {
                // We have multiple AsyncIterators iterating the sequence
                fatalError("This should never happen since we only allow a single Iterator to be created")
            }

            self._state = .modify

            // We have to check here again since we might have a producer interleave next and suspendNext
            guard let element = streaming.buffer.popFirst() else {
                // There is nothing in the buffer to fulfil the demand so we to store the continuation.
                streaming.consumerContinuation = continuation
                self._state = .streaming(streaming)

                return .none
            }
            // We have an element to fulfil the demand right away.

            let shouldProduceMore = streaming.backPressureStrategy.didConsume(element: element)
            streaming.hasOutstandingDemand = shouldProduceMore

            guard shouldProduceMore else {
                // We don't have any new demand, so we can just return the element.
                self._state = .streaming(streaming)
                return .resumeConsumerWithElement(continuation, element)
            }
            // There is demand and we have to resume our producers
            let producers = Array(streaming.producerContinuations.map { $0.1 })
            streaming.producerContinuations.removeAll()
            self._state = .streaming(streaming)
            return .resumeConsumerWithElementAndProducers(continuation, element, producers)

        case .sourceFinished(var sourceFinished):
            // Check if we have an element left in the buffer and return it
            self._state = .modify

            guard let element = sourceFinished.buffer.popFirst() else {
                // We are returning the queued failure now and can transition to finished
                self._state = .finished(iteratorInitialized: sourceFinished.iteratorInitialized)

                return .resumeConsumerWithFailureAndCallOnTermination(
                    continuation,
                    sourceFinished.failure,
                    sourceFinished.onTermination
                )
            }
            self._state = .sourceFinished(sourceFinished)

            return .resumeConsumerWithElement(continuation, element)

        case .finished:
            return .resumeConsumerWithNil(continuation)

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }

    /// Actions returned by `cancelNext()`.
    enum CancelNextAction {
        /// Indicates that the continuation should be resumed with nil, the producers should be finished and call onTermination.
        case resumeConsumerWithNilAndCallOnTermination(CheckedContinuation<Element?, Error>, (() -> Void)?)
        /// Indicates that the producers should be finished and call onTermination.
        case failProducersAndCallOnTermination([(Result<Void, Error>) -> Void], (() -> Void)?)
    }

    mutating func cancelNext() -> CancelNextAction? {
        switch self._state {
        case .initial:
            // We need to transition to streaming before we can suspend
            fatalError("AsyncStream internal inconsistency")

        case .streaming(let streaming):
            self._state = .finished(iteratorInitialized: streaming.iteratorInitialized)

            guard let consumerContinuation = streaming.consumerContinuation else {
                return .failProducersAndCallOnTermination(
                    Array(streaming.producerContinuations.map { $0.1 }),
                    streaming.onTermination
                )
            }
            precondition(
                streaming.producerContinuations.isEmpty,
                "Internal inconsistency. Unexpected producer continuations."
            )
            return .resumeConsumerWithNilAndCallOnTermination(
                consumerContinuation,
                streaming.onTermination
            )

        case .sourceFinished, .finished:
            return .none

        case .modify:
            fatalError("AsyncStream internal inconsistency")
        }
    }
}

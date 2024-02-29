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

/// A struct that acts as a source asynchronous sequence.
///
/// The ``AsyncNonThrowingBackPressuredStream`` provides a ``AsyncNonThrowingBackPressuredStream/Source`` to
/// write values to the stream. The source exposes the internal backpressure of the asynchronous sequence to the
/// external producer. This allows to bridge both synchronous and asynchronous producers into an asynchronous sequence.
///
/// ## Using an AsyncNonThrowingBackPressuredStream
///
/// To use an ``AsyncNonThrowingBackPressuredStream`` you have to create a new stream with it's source first by calling
/// the ``AsyncNonThrowingBackPressuredStream/makeStream(of:backpressureStrategy:)`` method.
/// Afterwards, you can pass the source to the producer and the stream to the consumer.
///
/// ```
/// let (stream, source) = AsyncNonThrowingBackPressuredStream<Int>.makeStream(
///     backpressureStrategy: .watermark(low: 2, high: 4)
/// )
///
/// try await withThrowingTaskGroup(of: Void.self) { group in
///     group.addTask {
///         try await source.write(1)
///         try await source.write(2)
///         try await source.write(3)
///     }
///
///     for await element in stream {
///         print(element)
///     }
/// }
/// ```
///
/// The source also exposes synchronous write methods that communicate the backpressure via callbacks.
public struct AsyncNonThrowingBackPressuredStream<Element>: AsyncSequence {
    /// A private class to give the ``AsyncNonThrowingBackPressuredStream`` a deinit so we
    /// can tell the producer when any potential consumer went away.
    private final class _Backing: Sendable {
        /// The underlying storage.
        fileprivate let storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>

        init(storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>) {
            self.storage = storage
        }

        deinit {
            storage.sequenceDeinitialized()
        }
    }

    /// The backing storage.
    private let backing: _Backing

    /// Initializes a new ``AsyncNonThrowingBackPressuredStream`` and an ``AsyncNonThrowingBackPressuredStream/Source``.
    ///
    /// - Parameters:
    ///   - elementType: The element type of the stream.
    ///   - backPressureStrategy: The backpressure strategy that the stream should use.
    /// - Returns: A tuple containing the stream and its source. The source should be passed to the
    ///   producer while the stream should be passed to the consumer.
    public static func makeStream(
        of elementType: Element.Type = Element.self,
        backPressureStrategy: Source.BackPressureStrategy
    ) -> (`Self`, Source) {
        let storage = _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>(
            backPressureStrategy: backPressureStrategy.internalBackPressureStrategy
        )
        let source = Source(storage: storage)

        return (.init(storage: storage), source)
    }

    init(storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>) {
        self.backing = .init(storage: storage)
    }
}

extension AsyncNonThrowingBackPressuredStream {
    /// A struct to interface between producer code and an asynchronous stream.
    ///
    /// Use this source to provide elements to the stream by calling one of the `write` methods, then terminate the stream normally
    /// by calling the `finish()` method. You can also use the source's `finish(throwing:)` method to terminate the stream by
    /// throwing an error.
    ///
    /// - Important: You must  terminate the source by calling one of the `finish` methods otherwise the stream's iterator
    /// will never terminate.
    public struct Source: Sendable {
        /// A strategy that handles the backpressure of the asynchronous stream.
        public struct BackPressureStrategy: Sendable {
            var internalBackPressureStrategy: _AsyncBackPressuredStreamInternalBackPressureStrategy<Element>

            /// A backpressure strategy using a high and low watermark to suspend and resume production respectively.
            ///
            /// - Parameters:
            ///   - low: When the number of buffered elements drops below the low watermark, producers will be resumed.
            ///   - high: When the number of buffered elements rises above the high watermark, producers will be suspended.
            public static func watermark(low: Int, high: Int) -> BackPressureStrategy {
                .init(
                    internalBackPressureStrategy: .watermark(
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
            /// - Note, `waterLevelForElement` will be called on each element when it is written into the source and when
            /// it is consumed from the stream, so it is recommended to provide an function that runs in constant time.
            public static func watermark(
                low: Int,
                high: Int,
                waterLevelForElement: @escaping @Sendable (Element) -> Int
            ) -> BackPressureStrategy {
                .init(
                    internalBackPressureStrategy: .watermark(
                        .init(low: low, high: high, waterLevelForElement: waterLevelForElement)
                    )
                )
            }
        }

        /// A type that indicates the result of writing elements to the source.
        public enum WriteResult: Sendable {
            /// A token that is returned when the asynchronous stream's backpressure strategy indicated that production should
            /// be suspended. Use this token to enqueue a callback by  calling the ``enqueueCallback(_:)`` method.
            public struct CallbackToken: Sendable {
                let id: UInt
            }

            /// Indicates that more elements should be produced and written to the source.
            case produceMore

            /// Indicates that a callback should be enqueued.
            ///
            /// The associated token should be passed to the ``enqueueCallback(_:)`` method.
            case enqueueCallback(CallbackToken)
        }

        /// Backing class for the source used to hook a deinit.
        final class _Backing: Sendable {
            let storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>

            init(storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>) {
                self.storage = storage
            }

            // TODO: Double check
            deinit {
                self.storage.sourceDeinitialized()
            }
        }

        /// A callback to invoke when the stream finished.
        ///
        /// The stream finishes and calls this closure in the following cases:
        /// - No iterator was created and the sequence was deinited
        /// - An iterator was created and deinited
        /// - After ``finish(throwing:)`` was called and all elements have been consumed
        public var onTermination: (@Sendable () -> Void)? {
            set {
                self._backing.storage.onTermination = newValue
            }
            get {
                self._backing.storage.onTermination
            }
        }

        private var _backing: _Backing

        internal init(storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>) {
            self._backing = .init(storage: storage)
        }

        /// Writes new elements to the asynchronous stream.
        ///
        /// If there is a task consuming the stream and awaiting the next element then the task will get resumed with the
        /// first element of the provided sequence. If the asynchronous stream already terminated then this method will throw an error
        /// indicating the failure.
        ///
        /// - Parameter sequence: The elements to write to the asynchronous stream.
        /// - Returns: The result that indicates if more elements should be produced at this time.
        public func write<S>(contentsOf sequence: S) throws -> WriteResult where Element == S.Element, S: Sequence {
            switch try self._backing.storage.write(contentsOf: sequence) {
            case .produceMore:
                return .produceMore
            case .enqueueCallback(let callbackToken):
                return .enqueueCallback(.init(id: callbackToken.id))
            }
        }

        /// Write the element to the asynchronous stream.
        ///
        /// If there is a task consuming the stream and awaiting the next element then the task will get resumed with the
        /// provided element. If the asynchronous stream already terminated then this method will throw an error
        /// indicating the failure.
        ///
        /// - Parameter element: The element to write to the asynchronous stream.
        /// - Returns: The result that indicates if more elements should be produced at this time.
        public func write(_ element: Element) throws -> WriteResult {
            switch try self._backing.storage.write(contentsOf: CollectionOfOne(element)) {
            case .produceMore:
                return .produceMore
            case .enqueueCallback(let callbackToken):
                return .enqueueCallback(.init(id: callbackToken.id))
            }
        }

        /// Enqueues a callback that will be invoked once more elements should be produced.
        ///
        /// Call this method after ``write(contentsOf:)`` or ``write(:)`` returned ``WriteResult/enqueueCallback(_:)``.
        ///
        /// - Important: Enqueueing the same token multiple times is not allowed.
        ///
        /// - Parameters:
        ///   - callbackToken: The callback token.
        ///   - onProduceMore: The callback which gets invoked once more elements should be produced.
        public func enqueueCallback(
            callbackToken: WriteResult.CallbackToken,
            onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void
        ) {
            let callbackToken = AsyncBackPressuredStream<Element, Never>.Source.WriteResult.CallbackToken(
                id: callbackToken.id
            )
            self._backing.storage.enqueueProducer(callbackToken: callbackToken, onProduceMore: onProduceMore)
        }

        /// Cancel an enqueued callback.
        ///
        /// Call this method to cancel a callback enqueued by the ``enqueueCallback(callbackToken:onProduceMore:)`` method.
        ///
        /// - Note: This methods supports being called before ``enqueueCallback(callbackToken:onProduceMore:)`` is called and
        /// will mark the passed `callbackToken` as cancelled.
        ///
        /// - Parameter callbackToken: The callback token.
        public func cancelCallback(callbackToken: WriteResult.CallbackToken) {
            let callbackToken = AsyncBackPressuredStream<Element, Never>.Source.WriteResult.CallbackToken(
                id: callbackToken.id
            )
            self._backing.storage.cancelProducer(callbackToken: callbackToken)
        }

        /// Write new elements to the asynchronous stream and provide a callback which will be invoked once more elements should be produced.
        ///
        /// If there is a task consuming the stream and awaiting the next element then the task will get resumed with the
        /// first element of the provided sequence. If the asynchronous stream already terminated then `onProduceMore` will be invoked with
        /// a `Result.failure`.
        ///
        /// - Parameters:
        ///   - sequence: The elements to write to the asynchronous stream.
        ///   - onProduceMore: The callback which gets invoked once more elements should be produced. This callback might be
        ///   invoked during the call to ``write(contentsOf:onProduceMore:)``.
        public func write<S>(contentsOf sequence: S, onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void)
        where Element == S.Element, S: Sequence {
            do {
                let writeResult = try self.write(contentsOf: sequence)

                switch writeResult {
                case .produceMore:
                    onProduceMore(Result<Void, Error>.success(()))

                case .enqueueCallback(let callbackToken):
                    self.enqueueCallback(callbackToken: callbackToken, onProduceMore: onProduceMore)
                }
            } catch {
                onProduceMore(.failure(error))
            }
        }

        /// Writes the element to the asynchronous stream.
        ///
        /// If there is a task consuming the stream and awaiting the next element then the task will get resumed with the
        /// provided element. If the asynchronous stream already terminated then `onProduceMore` will be invoked with
        /// a `Result.failure`.
        ///
        /// - Parameters:
        ///   - sequence: The element to write to the asynchronous stream.
        ///   - onProduceMore: The callback which gets invoked once more elements should be produced. This callback might be
        ///   invoked during the call to ``write(_:onProduceMore:)``.
        public func write(_ element: Element, onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void) {
            self.write(contentsOf: CollectionOfOne(element), onProduceMore: onProduceMore)
        }

        /// Write new elements to the asynchronous stream.
        ///
        /// If there is a task consuming the stream and awaiting the next element then the task will get resumed with the
        /// first element of the provided sequence. If the asynchronous stream already terminated then this method will throw an error
        /// indicating the failure.
        ///
        /// This method returns once more elements should be produced.
        ///
        /// - Parameters:
        ///   - sequence: The elements to write to the asynchronous stream.
        public func write<S>(contentsOf sequence: S) async throws where Element == S.Element, S: Sequence {
            let writeResult = try { try self.write(contentsOf: sequence) }()

            switch writeResult {
            case .produceMore:
                return

            case .enqueueCallback(let callbackToken):
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        self.enqueueCallback(
                            callbackToken: callbackToken,
                            onProduceMore: { result in
                                switch result {
                                case .success():
                                    continuation.resume(returning: ())
                                case .failure(let error):
                                    continuation.resume(throwing: error)
                                }
                            }
                        )
                    }
                } onCancel: {
                    self.cancelCallback(callbackToken: callbackToken)
                }
            }
        }

        /// Write new element to the asynchronous stream.
        ///
        /// If there is a task consuming the stream and awaiting the next element then the task will get resumed with the
        /// provided element. If the asynchronous stream already terminated then this method will throw an error
        /// indicating the failure.
        ///
        /// This method returns once more elements should be produced.
        ///
        /// - Parameters:
        ///   - sequence: The element to write to the asynchronous stream.
        public func write(_ element: Element) async throws {
            try await self.write(contentsOf: CollectionOfOne(element))
        }

        /// Write the elements of the asynchronous sequence to the asynchronous stream.
        ///
        /// This method returns once the provided asynchronous sequence or the  the asynchronous stream finished.
        ///
        /// - Important: This method does not finish the source if consuming the upstream sequence terminated.
        ///
        /// - Parameters:
        ///   - sequence: The elements to write to the asynchronous stream.
        public func write<S>(contentsOf sequence: S) async throws where Element == S.Element, S: AsyncSequence {
            for try await element in sequence {
                try await self.write(contentsOf: CollectionOfOne(element))
            }
        }

        /// Indicates that the production terminated.
        ///
        /// After all buffered elements are consumed the next iteration point will return `nil`.
        ///
        /// Calling this function more than once has no effect. After calling finish, the stream enters a terminal state and doesn't accept
        /// new elements.
        public func finish() {
            self._backing.storage.finish(nil)
        }
    }
}

extension AsyncNonThrowingBackPressuredStream {
    /// The asynchronous iterator for iterating an asynchronous stream.
    ///
    /// This type is not `Sendable`. Don't use it from multiple
    /// concurrent contexts. It is a programmer error to invoke `next()` from a
    /// concurrent context that contends with another such call, which
    /// results in a call to `fatalError()`.
    public struct Iterator: AsyncIteratorProtocol {
        private class _Backing {
            let storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>

            init(storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>) {
                self.storage = storage
                self.storage.iteratorInitialized()
            }

            deinit {
                self.storage.iteratorDeinitialized()
            }
        }

        private let backing: _Backing

        init(storage: _AsyncBackPressuredStreamBackPressuredStorage<Element, Never>) {
            self.backing = .init(storage: storage)
        }

        /// The next value from the asynchronous stream.
        ///
        /// When `next()` returns `nil`, this signifies the end of the
        /// `AsyncThrowingStream`.
        ///
        /// It is a programmer error to invoke `next()` from a concurrent context
        /// that contends with another such call, which results in a call to
        ///  `fatalError()`.
        ///
        /// If you cancel the task this iterator is running in while `next()` is
        /// awaiting a value, the `AsyncThrowingStream` terminates. In this case,
        /// `next()` may return `nil` immediately, or else return `nil` on
        /// subsequent calls.
        public mutating func next() async -> Element? {
            try! await self.backing.storage.next()
        }
    }

    /// Creates the asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    public func makeAsyncIterator() -> Iterator {
        Iterator(storage: self.backing.storage)
    }
}

extension AsyncNonThrowingBackPressuredStream: Sendable where Element: Sendable {}

@available(*, unavailable)
extension AsyncNonThrowingBackPressuredStream.Iterator: Sendable {}

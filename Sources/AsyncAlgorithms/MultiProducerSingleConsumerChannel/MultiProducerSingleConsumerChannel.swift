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

#if compiler(>=6.0)
/// An error that is thrown from the various `send` methods of the
/// ``MultiProducerSingleConsumerChannel/Source``.
///
/// This error is thrown when the channel is already finished when
/// trying to send new elements to the source.
public struct MultiProducerSingleConsumerChannelAlreadyFinishedError: Error {
    @usableFromInline
    init() {}
}

/// A multi producer single consumer channel.
///
/// The ``MultiProducerSingleConsumerChannel`` provides a ``MultiProducerSingleConsumerChannel/Source`` to
/// send values to the channel. The source exposes the internal backpressure of the asynchronous sequence to the
/// producer. Additionally, the source can be used from synchronous and asynchronous contexts.
///
///
/// ## Using a MultiProducerSingleConsumerChannel
///
/// To use a ``MultiProducerSingleConsumerChannel`` you have to create a new channel with it's source first by calling
/// the ``MultiProducerSingleConsumerChannel/makeChannel(of:throwing:BackpressureStrategy:)`` method.
/// Afterwards, you can pass the source to the producer and the channel to the consumer.
///
/// ```
/// let (channel, source) = MultiProducerSingleConsumerChannel<Int, Never>.makeChannel(
///     backpressureStrategy: .watermark(low: 2, high: 4)
/// )
/// ```
///
/// ### Asynchronous producers
///
/// Values can be send to the source from asynchronous contexts using ``MultiProducerSingleConsumerChannel/Source/send(_:)-9b5do``
/// and ``MultiProducerSingleConsumerChannel/Source/send(contentsOf:)-4myrz``. Backpressure results in calls
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
/// ### Synchronous producers
///
/// Values can also be send to the source from synchronous context. Backpressure is also exposed on the synchronous contexts; however,
/// it is up to the caller to decide how to properly translate the backpressure to underlying producer e.g. by blocking the thread.
///
/// ## Finishing the source
///
/// To properly notify the consumer if the production of values has been finished the source's ``MultiProducerSingleConsumerChannel/Source/finish(throwing:)`` **must** be called.
public struct MultiProducerSingleConsumerChannel<Element, Failure: Error>: AsyncSequence {
    /// A private class to give the ``MultiProducerSingleConsumerChannel`` a deinit so we
    /// can tell the producer when any potential consumer went away.
    private final class _Backing: Sendable {
        /// The underlying storage.
        fileprivate let storage: _Storage

        init(storage: _Storage) {
            self.storage = storage
        }

        deinit {
            storage.sequenceDeinitialized()
        }
    }

    /// The backing storage.
    private let backing: _Backing

    @frozen
    public struct ChannelAndStream: ~Copyable {
        public var channel: MultiProducerSingleConsumerChannel
        public var source: Source

        public init(
            channel: MultiProducerSingleConsumerChannel,
            source: consuming Source
        ) {
            self.channel = channel
            self.source = source
        }
    }

    /// Initializes a new ``MultiProducerSingleConsumerChannel`` and an ``MultiProducerSingleConsumerChannel/Source``.
    ///
    /// - Parameters:
    ///   - elementType: The element type of the channel.
    ///   - failureType: The failure type of the channel.
    ///   - BackpressureStrategy: The backpressure strategy that the channel should use.
    /// - Returns: A tuple containing the channel and its source. The source should be passed to the
    ///   producer while the channel should be passed to the consumer.
    public static func makeChannel(
        of elementType: Element.Type = Element.self,
        throwing failureType: Failure.Type = Never.self,
        backpressureStrategy: Source.BackpressureStrategy
    ) -> ChannelAndStream {
        let storage = _Storage(
            backpressureStrategy: backpressureStrategy.internalBackpressureStrategy
        )
        let source = Source(storage: storage)

        return .init(channel: .init(storage: storage), source: source)
    }

    init(storage: _Storage) {
        self.backing = .init(storage: storage)
    }
}

extension MultiProducerSingleConsumerChannel {
    /// A struct to send values to the channel.
    ///
    /// Use this source to provide elements to the channel by calling one of the `send` methods.
    ///
    /// - Important: You must terminate the source by calling ``finish(throwing:)``.
    public struct Source: ~Copyable, Sendable {
        /// A strategy that handles the backpressure of the channel.
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
            /// - Note, `waterLevelForElement` will be called on each element when it is written into the source and when
            /// it is consumed from the channel, so it is recommended to provide an function that runs in constant time.
            public static func watermark(
                low: Int,
                high: Int,
                waterLevelForElement: @escaping @Sendable (Element) -> Int // TODO: In the future this should become sending
            ) -> BackpressureStrategy {
                .init(
                    internalBackpressureStrategy: .watermark(
                        .init(low: low, high: high, waterLevelForElement: waterLevelForElement)
                    )
                )
            }

            /// An unbounded backpressure strategy.
            ///
            /// - Important: Only use this strategy if the production of elements is limited through some other mean. Otherwise
            /// an unbounded backpressure strategy can result in infinite memory usage and open your application to denial of service
            /// attacks.
            public static func unbounded() -> BackpressureStrategy {
                .init(
                    internalBackpressureStrategy: .unbounded(.init())
                )
            }
        }

        /// A type that indicates the result of sending elements to the source.
        public enum SendResult: ~Copyable, Sendable {
            /// A token that is returned when the channel's backpressure strategy indicated that production should
            /// be suspended. Use this token to enqueue a callback by  calling the ``enqueueCallback(_:)`` method.
            public struct CallbackToken: Sendable {
                @usableFromInline
                let _id: UInt64

                @usableFromInline
                init(id: UInt64) {
                    self._id = id
                }
            }

            /// Indicates that more elements should be produced and written to the source.
            case produceMore

            /// Indicates that a callback should be enqueued.
            ///
            /// The associated token should be passed to the ``enqueueCallback(_:)`` method.
            case enqueueCallback(CallbackToken)
        }


        /// A callback to invoke when the channel finished.
        ///
        /// The channel finishes and calls this closure in the following cases:
        /// - No iterator was created and the sequence was deinited
        /// - An iterator was created and deinited
        /// - After ``finish(throwing:)`` was called and all elements have been consumed
        public var onTermination: (@Sendable () -> Void)? {
            set {
                self._storage.onTermination = newValue
            }
            get {
                self._storage.onTermination
            }
        }

        @usableFromInline
        let _storage: _Storage

        internal init(storage: _Storage) {
            self._storage = storage
        }

        deinit {
            self._storage.sourceDeinitialized()
        }


        /// Creates a new source which can be used to send elements to the channel concurrently.
        ///
        /// The channel will only automatically be finished if all existing sources have been deinited.
        ///
        /// - Returns: A new source for sending elements to the channel.
        public mutating func copy() -> Self {
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
        public mutating func send<S>(contentsOf sequence: sending S) throws -> SendResult where Element == S.Element, S: Sequence {
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
        public mutating func send(_ element: sending Element) throws -> SendResult {
            try self._storage.send(contentsOf: CollectionOfOne(element))
        }

        /// Enqueues a callback that will be invoked once more elements should be produced.
        ///
        /// Call this method after ``send(contentsOf:)-5honm`` or ``send(_:)-3jxzb`` returned ``SendResult/enqueueCallback(_:)``.
        ///
        /// - Important: Enqueueing the same token multiple times is not allowed.
        ///
        /// - Parameters:
        ///   - callbackToken: The callback token.
        ///   - onProduceMore: The callback which gets invoked once more elements should be produced.
        @inlinable
        public mutating func enqueueCallback(
            callbackToken: consuming SendResult.CallbackToken,
            onProduceMore: sending @escaping (Result<Void, Error>) -> Void
        ) {
            self._storage.enqueueProducer(callbackToken: callbackToken._id, onProduceMore: onProduceMore)
        }

        /// Cancel an enqueued callback.
        ///
        /// Call this method to cancel a callback enqueued by the ``enqueueCallback(callbackToken:onProduceMore:)`` method.
        ///
        /// - Note: This methods supports being called before ``enqueueCallback(callbackToken:onProduceMore:)`` is called and
        /// will mark the passed `callbackToken` as cancelled.
        ///
        /// - Parameter callbackToken: The callback token.
        @inlinable
        public mutating func cancelCallback(callbackToken: consuming SendResult.CallbackToken) {
            self._storage.cancelProducer(callbackToken: callbackToken._id)
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
            contentsOf sequence: sending S,
            onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void
        ) where Element == S.Element, S: Sequence {
            do {
                let sendResult = try self.send(contentsOf: sequence)

                switch consume sendResult {
                case .produceMore:
                    onProduceMore(Result<Void, Error>.success(()))

                case .enqueueCallback(let callbackToken):
                    self.enqueueCallback(callbackToken: callbackToken, onProduceMore: onProduceMore)
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
            _ element: sending Element,
            onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void
        ) {
            self.send(contentsOf: CollectionOfOne(element), onProduceMore: onProduceMore)
        }

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
        public mutating func send<S>(contentsOf sequence: sending S) async throws where Element == S.Element, S: Sequence {
            let sendResult = try { try self.send(contentsOf: sequence) }()

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
        public mutating func send(_ element: sending Element) async throws {
            try await self.send(contentsOf: CollectionOfOne(element))
        }

        /// Send the elements of the asynchronous sequence to the channel.
        ///
        /// This method returns once the provided asynchronous sequence or  the channel finished.
        ///
        /// - Important: This method does not finish the source if consuming the upstream sequence terminated.
        ///
        /// - Parameters:
        ///   - sequence: The elements to send to the channel.
        @inlinable
        public mutating func send<S>(contentsOf sequence: sending S) async throws where Element == S.Element, S: AsyncSequence {
            for try await element in sequence {
                try await self.send(contentsOf: CollectionOfOne(element))
            }
        }

        /// Indicates that the production terminated.
        ///
        /// After all buffered elements are consumed the next iteration point will return `nil` or throw an error.
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

extension MultiProducerSingleConsumerChannel {
    /// The asynchronous iterator for iterating the channel.
    ///
    /// This type is not `Sendable`. Don't use it from multiple
    /// concurrent contexts. It is a programmer error to invoke `next()` from a
    /// concurrent context that contends with another such call, which
    /// results in a call to `fatalError()`.
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        final class _Backing {
            @usableFromInline
            let storage: _Storage

            init(storage: _Storage) {
                self.storage = storage
                self.storage.iteratorInitialized()
            }

            deinit {
                self.storage.iteratorDeinitialized()
            }
        }

        @usableFromInline
        let _backing: _Backing

        init(storage: _Storage) {
            self._backing = .init(storage: storage)
        }

        @_disfavoredOverload
        @inlinable
        public mutating func next() async throws -> Element? {
            try await self._backing.storage.next(isolation: nil)
        }

        @inlinable
        public mutating func next(
            isolation actor: isolated (any Actor)? = #isolation
        ) async throws(Failure) -> Element? {
            do {
                return try await self._backing.storage.next(isolation: actor)
            } catch {
                throw error as! Failure
            }
        }
    }

    /// Creates the asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    public func makeAsyncIterator() -> Iterator {
        Iterator(storage: self.backing.storage)
    }
}

extension MultiProducerSingleConsumerChannel: Sendable where Element: Sendable {}

@available(*, unavailable)
extension MultiProducerSingleConsumerChannel.Iterator: Sendable {}
#endif

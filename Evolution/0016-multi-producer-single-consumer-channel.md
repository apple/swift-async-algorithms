# MultiProducerSingleConsumerAsyncChannel

* Proposal: [SAA-0016](0016-multi-producer-single-consumer-channel.md)
* Authors: [Franz Busch](https://github.com/FranzBusch)
* Status: **Implemented**

## Revision
- 2023/12/18: Migrate proposal from Swift Evolution to Swift Async Algorithms.
- 2023/12/19: Add element size dependent strategy
- 2024/05/19: Rename to multi producer single consumer channel
- 2024/05/28: Add unbounded strategy
- 2025/03/24: Adopt `~Copyable` for correct semantics and better performance.

## Introduction

[SE-0314](https://github.com/apple/swift-evolution/blob/main/proposals/0314-async-stream.md)
introduced new `Async[Throwing]Stream` types which act as root asynchronous
sequences. These two types allow bridging from synchronous callbacks such as
delegates to an asynchronous sequence. This proposal adds a new root primitive
with the goal of modeling asynchronous multi-producer-single-consumer systems.

## Motivation

After using the `AsyncSequence` protocol, the `Async[Throwing]Stream` types, and
the `Async[Throwing]Channel` types extensively over the past years, we learned
that there is a gap in the ecosystem for a type that provides strict
multi-producer-single-consumer guarantees with external backpressure support.
Additionally, any stream/channel like type needs to have a clear definition
about the following behaviors:

1. Backpressure
2. Multi/single consumer support
3. Downstream consumer termination
4. Upstream producer termination

The below sections are providing a detailed explanation of each of those.

### Backpressure

In general, backpressure is the mechanism that prevents a fast producer from
overwhelming a slow consumer. It helps the stability of the overall system by
regulating the flow of data between different components. Additionally, it
allows us to put an upper bound on the resource consumption of a system. In reality,
backpressure is used in almost all networked applications.

In Swift, asynchronous sequences also have the concept of internal backpressure.
This is modeled by the pull-based implementation where a consumer has to call
`next` on the `AsyncIterator`. In this model, there is no way for a consumer to
overwhelm a producer since the producer controls the rate of pulling elements.

However, the internal backpressure of an asynchronous sequence isn't the only
backpressure in play. There is also the source backpressure that is producing
the actual elements. For a backpressured system, it is important that every
component of such a system is aware of the backpressure of its consumer and its
producer.

Let's take a quick look at how our current root asynchronous sequences are handling
this.

`Async[Throwing]Stream` aims to support backpressure by providing a configurable
buffer and returning `Async[Throwing]Stream.Continuation.YieldResult` which
contains the current buffer depth from the `yield()` method. However, only
providing the current buffer depth on `yield()` is not enough to bridge a
backpressured system into an asynchronous sequence since this can only be used
as a "stop" signal, but we are missing a signal to indicate resuming the
production. The only viable backpressure strategy that can be implemented with
the current API is a timed backoff where we stop producing for some period of
time and then speculatively produce again. This is a very inefficient pattern
that produces high latencies and inefficient use of resources.

`Async[Throwing]Channel` is a multi-producer-multi-consumer channel that only
supports asynchronous producers. Additionally, the backpressure strategy is
fixed by a buffer size of 1 element per producer.

We are currently lacking a type that supports a configurable backpressure
strategy and both asynchronous and synchronous producers.

### Multi/single consumer support

The `AsyncSequence` protocol itself makes no assumptions about whether the
implementation supports multiple consumers or not. This allows the creation of
unicast and multicast asynchronous sequences. The difference between a unicast
and multicast asynchronous sequence is if they allow multiple iterators to be
created. `AsyncStream` does support the creation of multiple iterators and it
does handle multiple consumers correctly. On the other hand,
`AsyncThrowingStream` also supports multiple iterators but does `fatalError`
when more than one iterator has to suspend. The original proposal states:

> As with any sequence, iterating over an AsyncStream multiple times, or
creating multiple iterators and iterating over them separately, may produce an
unexpected series of values.

While that statement leaves room for any behavior, we learned that a clear distinction
of behavior for root asynchronous sequences is beneficial; especially when it comes to
how transformation algorithms are applied on top.

### Downstream consumer termination

Downstream consumer termination allows the producer to notify the consumer that
no more values are going to be produced. `Async[Throwing]Stream` does support
this by calling the `finish()` or `finish(throwing:)` methods of the
`Async[Throwing]Stream.Continuation`. However, `Async[Throwing]Stream` does not
handle the case that the `Continuation` may be `deinit`ed before one of the
finish methods is called. This currently leads to async streams that never
terminate.

### Upstream producer termination

Upstream producer termination is the inverse of downstream consumer termination,
where the producer is notified once the consumption has terminated. Currently,
`Async[Throwing]Stream` does expose the `onTermination` property on the
`Continuation`. The `onTermination` closure is invoked once the consumer has
terminated. The consumer can terminate in four separate cases:

1. The asynchronous sequence was `deinit`ed and no iterator was created.
2. The iterator was `deinit`ed and the asynchronous sequence is unicast.
3. The consuming task is canceled.
4. The asynchronous sequence returned `nil` or threw.

`Async[Throwing]Stream` currently invokes `onTermination` in all cases; however,
since `Async[Throwing]Stream` supports multiple consumers (as discussed in the
`Multi/single consumer support` section), a single consumer task being canceled
leads to the termination of all consumers. This is not expected from multicast
asynchronous sequences in general.

## Proposed solution

The above motivation lays out the expected behaviors for any consumer/producer
system and compares them to the behaviors of `Async[Throwing]Stream` and
`Async[Throwing]Channel`.

This section proposes a new type called `MultiProducerSingleConsumerAsyncChannel`
that implements all of the above-mentioned behaviors. Importantly, this proposed
solution is taking advantage of `~Copyable` types to model the
multi-producer-single-consumer behavior. While the current `AsyncSequence`
protocols are not supporting `~Copyable` types, we provide a way to convert the
proposed channel to an asynchronous sequence. This leaves us room to support any
potential future asynchronous streaming protocol that supports `~Copyable`.

### Creating a MultiProducerSingleConsumerAsyncChannel

You can create an `MultiProducerSingleConsumerAsyncChannel` instance using the
`makeChannel(of:backpressureStrategy:)` method. This method returns you the
channel and the source. The source can be used to send new values to the
asynchronous channel. The new API specifically provides a
multi-producer/single-consumer pattern.

```swift
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)

// The channel and source can be extracted from the returned type
let channel = consume channelAndSource.channel
let source = consume channelAndSource.source
```

The new proposed APIs offer two different backpressure strategies:
- Watermark: Using a low and high watermark.
- Unbounded: Unbounded buffering of the channel. **Only** use this if the
  production is limited through some other means.

The source is used to send values to the channel. It provides different APIs for
synchronous and asynchronous producers. All of the APIs are relaying the
backpressure of the channel. The synchronous multi-step APIs are the foundation
for all other APIs. Below is an example of how it can be used:

```swift
do {
    let sendResult = try source.send(contentsOf: sequence)
    
    switch sendResult {
    case .produceMore:
       // Trigger more production in the underlying system
    
    case .enqueueCallback(let callbackHandle):
        // There are enough values in the channel already. We need to enqueue
        // a callback to get notified when we should produce more.
        callbackHandle.enqueueCallback(onProduceMore: { result in
            switch result {
            case .success:
                // Trigger more production in the underlying system
            case .failure(let error):
                // Terminate the underlying producer
            }
        })
    }
} catch {
    // `send(contentsOf:)` throws if the channel already terminated
}
```

The above API offers the most control and highest performance when bridging a
synchronous producer to a `MultiProducerSingleConsumerAsyncChannel`. First, you have
to send values using the `send(contentsOf:)` which returns a `SendResult`. The
result either indicates that more values should be produced or that a callback
should be enqueued by calling the `enqueueCallback(onProduceMore:)` method.
This callback is invoked once the backpressure strategy
decides that more values should be produced. This API aims to offer the most
flexibility with the greatest performance. The callback only has to be allocated
in the case where the producer needs to pause production.

Additionally, the above API is the building block for some higher-level and
easier-to-use APIs to send values to the channel. Below is an
example of the two higher-level APIs.

```swift
// Writing new values and providing a callback when to produce more
try source.send(contentsOf: sequence, onProduceMore: { result in
    switch result {
    case .success:
        // Trigger more production
    case .failure(let error):
        // Terminate the underlying producer
    }
})

// This method suspends until more values should be produced
try await source.send(contentsOf: sequence)
```

With the above APIs, we should be able to effectively bridge any system into a
`MultiProducerSingleConsumerAsyncChannel` regardless of whether the system is callback-based,
blocking, or asynchronous.

### Multi producer

To support multiple producers, the source offers a `copy` method to produce a new
source. The source is returned `sending`, so it is in a disconnected isolation
region from the original source, allowing it to be passed into a different isolation
region to concurrently produce elements.

```swift
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 5)
)
var channel = consume channelAndSource.channel
var source1 = consume channelAndSource.source
var source2 = source1.makeAdditionalSource()

group.addTask {
    try await source1.send(1)
}

group.addTask() {
    try await source2.send(2)
}

print(await channel.next()) // Prints either 1 or 2 depending on which child task runs first
print(await channel.next()) // Prints either 1 or 2 depending on which child task runs first
```

### Downstream consumer termination

> When reading the next two examples of termination behavior, keep in mind
that the newly proposed APIs are providing a strict single consumer channel.

Calling `finish()` terminates the downstream consumer. Below is an example of
this:

```swift
// Termination through calling finish
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)
var channel = consume channelAndSource.channel
var source = consume channelAndSource.source

try await source.send(1)
source.finish()

print(await channel.next()) // Prints Optional(1)
print(await channel.next()) // Prints nil
```

If the channel has a failure type it can also be finished with an error.

```swift
// Termination through calling finish
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    throwing: SomeError.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)
var channel = consume channelAndSource.channel
var source = consume channelAndSource.source

try await source.send(1)
source.finish(throwing: SomeError)

print(try await channel.next()) // Prints Optional(1)
print(try await channel.next()) // Throws SomeError
```

The other way to terminate the consumer is by deiniting the source. This has the
same effect as calling `finish()`. Since the source is a `~Copyable` type, this
will happen automatically when the source is last used or explicitly consumed.

```swift
// Termination through deiniting the source
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)
var channel = consume channelAndSource.channel
var source = consume channelAndSource.source

try await source.send(1)
_ = consume source // Explicitly consume the source

print(await channel.next()) // Prints Optional(1)
print(await channel.next()) // Prints nil
```

### Upstream producer termination

The producer will get notified about termination through the `onTerminate`
callback. Termination of the producer happens in the following scenarios:

```swift
// Termination through task cancellation
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)
var channel = consume channelAndSource.channel
var source = consume channelAndSource.source
source.setOnTerminationCallback { print("Terminated") }

let task = Task {
    await channel.next()
}
task.cancel() // Prints Terminated
```

```swift
// Termination through deiniting the channel
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)
var channel = consume channelAndSource.channel
var source = consume channelAndSource.source
source.setOnTerminationCallback { print("Terminated") }
_ = consume channel // Prints Terminated
```

```swift
// Termination through finishing the source and consuming the last element
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)
var channel = consume channelAndSource.channel
var source = consume channelAndSource.source
source.setOnTerminationCallback { print("Terminated") }

_ = try await source.send(1)
source.finish()

print(await channel.next()) // Prints Optional(1)
await channel.next() // Prints Terminated
```

```swift
// Termination through deiniting the last source and consuming the last element
let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
    of: Int.self,
    backpressureStrategy: .watermark(low: 2, high: 4)
)
var channel = consume channelAndSource.channel
var source1 = consume channelAndSource.source
var source2 = source1.makeAdditionalSource()
source1.setOnTerminationCallback { print("Terminated") }

_ = try await source1.send(1)
_ = consume source1
_ = try await source2.send(2)

print(await channel.next()) // Prints Optional(1)
print(await channel.next()) // Prints Optional(2)
_ = consume source2
await channel.next() // Prints Terminated
```

Similar to the downstream consumer termination, trying to send more elements after the
producer has been terminated will result in an error thrown from the send methods. 

## Detailed design

```swift
#if compiler(>=6.1)
/// An error that is thrown from the various `send` methods of the
/// ``MultiProducerSingleConsumerAsyncChannel/Source``.
///
/// This error is thrown when the channel is already finished when
/// trying to send new elements to the source.
public struct MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError: Error { }

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
/// the ``MultiProducerSingleConsumerAsyncChannel/makeChannel(of:throwing:BackpressureStrategy:)`` method.
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
/// Values can be send to the source from asynchronous contexts using ``MultiProducerSingleConsumerAsyncChannel/Source/send(_:)-8eo96``
/// and ``MultiProducerSingleConsumerAsyncChannel/Source/send(contentsOf:)``. Backpressure results in calls
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
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct MultiProducerSingleConsumerAsyncChannel<Element, Failure: Error>: ~Copyable {
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
    public struct ChannelAndStream : ~Copyable {
        /// The channel.
        public var channel: MultiProducerSingleConsumerAsyncChannel
        /// The source.
        public var source: Source
    }

    /// Initializes a new ``MultiProducerSingleConsumerAsyncChannel`` and an ``MultiProducerSingleConsumerAsyncChannel/Source``.
    ///
    /// - Parameters:
    ///   - elementType: The element type of the channel.
    ///   - failureType: The failure type of the channel.
    ///   - backpressureStrategy: The backpressure strategy that the channel should use.
    /// - Returns: A tuple containing the channel and its source. The source should be passed to the
    ///   producer while the channel should be passed to the consumer.
    public static func makeChannel(
        of elementType: Element.Type = Element.self,
        throwing failureType: Failure.Type = Never.self,
        backpressureStrategy: Source.BackpressureStrategy
    ) -> ChannelAndStream

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
    public func next(isolation: isolated (any Actor)? = #isolation) async throws(Failure) -> Element?
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel {
    /// A struct to send values to the channel.
    ///
    /// Use this source to provide elements to the channel by calling one of the `send` methods.
    public struct Source: ~Copyable, Sendable {
        /// A struct representing the backpressure of the channel.
        public struct BackpressureStrategy: Sendable {
            /// A backpressure strategy using a high and low watermark to suspend and resume production respectively.
            ///
            /// - Parameters:
            ///   - low: When the number of buffered elements drops below the low watermark, producers will be resumed.
            ///   - high: When the number of buffered elements rises above the high watermark, producers will be suspended.
            public static func watermark(low: Int, high: Int) -> BackpressureStrategy

            /// A backpressure strategy using a high and low watermark to suspend and resume production respectively.
            ///
            /// - Parameters:
            ///   - low: When the number of buffered elements drops below the low watermark, producers will be resumed.
            ///   - high: When the number of buffered elements rises above the high watermark, producers will be suspended.
            ///   - waterLevelForElement: A closure used to compute the contribution of each buffered element to the current water level.
            ///
            /// - Note, `waterLevelForElement` will be called on each element when it is written into the source and when
            /// it is consumed from the channel, so it is recommended to provide a function that runs in constant time.
            public static func watermark(low: Int, high: Int, waterLevelForElement: @escaping @Sendable (borrowing Element) -> Int) -> BackpressureStrategy

            /// An unbounded backpressure strategy.
            ///
            /// - Important: Only use this strategy if the production of elements is limited through some other mean. Otherwise
            /// an unbounded backpressure strategy can result in infinite memory usage and cause
            /// your process to run out of memory.
            public static func unbounded() -> BackpressureStrategy
        }

        /// A type that indicates the result of sending elements to the source.
        public enum SendResult: ~Copyable, Sendable {
            /// A handle that is returned when the channel's backpressure strategy indicated that production should
            /// be suspended. Use this handle to enqueue a callback by  calling the ``CallbackHandle/enqueueCallback(onProduceMore:)`` method.
            ///
            /// - Important: ``CallbackHandle/enqueueCallback(onProduceMore:)`` and ``CallbackHandle/cancelCallback()`` must
            /// only be called once.
            public struct CallbackHandle: Sendable, Hashable {
                /// Enqueues a callback that will be invoked once more elements should be produced.
                ///
                /// - Important: Calling enqueue more than once is **not allowed**.
                ///
                /// - Parameters:
                ///   - onProduceMore: The callback which gets invoked once more elements should be produced.
                @inlinable
                public mutating func enqueueCallback(
                  onProduceMore: sending @escaping (Result<Void, Error>) -> Void
                )
                
                /// Cancel an enqueued callback.
                ///
                /// - Note: This methods supports being called before ``enqueueCallback(onProduceMore:)`` is called.
                ///
                /// - Important: Calling enqueue more than once is **not allowed**.
                @inlinable
                public mutating func cancelCallback()
            }

            /// Indicates that more elements should be produced and send to the source.
            case produceMore

            /// Indicates that a callback should be enqueued.
            case enqueueCallback(CallbackHandle)
        }

        /// A callback to invoke when the channel finished.
        ///
        /// This is called after the last element has been consumed by the channel.
        public func setOnTerminationCallback(_ callback: @escaping @Sendable () -> Void)

        /// Creates a new source which can be used to send elements to the channel concurrently.
        ///
        /// The channel will only automatically be finished if all existing sources have been deinited.
        ///
        /// - Returns: A new source for sending elements to the channel.
        public mutating func makeAdditionalSource() -> Source

        /// Sends new elements to the channel.
        ///
        /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
        /// first element of the provided sequence. If the channel already terminated then this method will throw an error
        /// indicating the failure.
        ///
        /// - Parameter sequence: The elements to send to the channel.
        /// - Returns: The result that indicates if more elements should be produced at this time.
        public mutating func send<S>(
            contentsOf sequence: consuming sending S
        ) throws -> SendResult where Element == S.Element, S: Sequence

        /// Send the element to the channel.
        ///
        /// If there is a task consuming the channel and awaiting the next element then the task will get resumed with the
        /// provided element. If the channel already terminated then this method will throw an error
        /// indicating the failure.
        ///
        /// - Parameter element: The element to send to the channel.
        /// - Returns: The result that indicates if more elements should be produced at this time.
        public mutating func send(_ element: sending consuming Element) throws -> SendResult

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
        public mutating func send<S>(
            contentsOf sequence: consuming sending S,
            onProduceMore: @escaping @Sendable (Result<Void, Error>) -> Void
        ) where Element == S.Element, S: Sequence

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
        public mutating func send(
            _ element: consuming sending Element,
            onProduceMore: @escaping @Sendable (Result<Void, Error>
        ) -> Void)

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
        public mutating func send<S>(
            contentsOf sequence: consuming sending S
        ) async throws where Element == S.Element, S: Sequence

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
        public mutating func send(_ element: consuming sending Element) async throws

        /// Send the elements of the asynchronous sequence to the channel.
        ///
        /// This method returns once the provided asynchronous sequence or the channel finished.
        ///
        /// - Important: This method does not finish the source if consuming the upstream sequence terminated.
        ///
        /// - Parameters:
        ///   - sequence: The elements to send to the channel.
        public mutating func send<S>(
            contentsOf sequence: consuming sending S
        ) async throws where Element: Sendable, Element == S.Element, S: Sendable, S: AsyncSequence

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
        public consuming func finish(throwing error: Failure? = nil)
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension MultiProducerSingleConsumerAsyncChannel {
    /// Converts the channel to an asynchronous sequence for consumption.
    ///
    /// - Important: The returned asynchronous sequence only supports a single iterator to be created and
    /// will fatal error at runtime on subsequent calls to `makeAsyncIterator`.
    public consuming func asyncSequence() -> some (AsyncSequence<Element, Failure> & Sendable)
}
```

## Comparison to other root asynchronous primitives

### swift-async-algorithm: AsyncChannel

The `AsyncChannel` is a multi-consumer/multi-producer root asynchronous sequence
which can be used to communicate between two tasks. It only offers asynchronous
production APIs and has an effective buffer of one per producer. This means that
any producer will be suspended until its value has been consumed. `AsyncChannel`
can handle multiple consumers and resumes them in FIFO order.

### swift-nio: NIOAsyncSequenceProducer

The NIO team has created their own root asynchronous sequence with the goal to
provide a high-performance sequence that can be used to bridge a NIO `Channel`
inbound stream into Concurrency. The `NIOAsyncSequenceProducer` is a highly
generic and fully inlinable type and quite unwieldy to use. This proposal is
heavily inspired by the learnings from this type but tries to create a more
flexible and easier-to-use API that fits into the standard library.

## Future directions

### Adaptive backpressure strategy

The high/low watermark strategy is common in networking code; however, there are
other strategies such as an adaptive strategy that we could offer in the future.
An adaptive strategy regulates the backpressure based on the rate of
consumption and production. With the proposed new APIs, we can easily add further
strategies.

### Support `~Copyable` elements

In the future, we can extend the channel to support `~Copyable` elements. We
only need an underlying buffer primitive that can hold `~Copyable` types, and the
continuations need to support `~Copyable` elements as well. By making the
channel not directly conform to `AsyncSequence`, we can support this down the
road.

## Alternatives considered

### Provide an `onTermination` callback to the factory method

During development of the new APIs, I first tried to provide the `onTermination`
callback in the `makeChannel` method. However, that showed significant usability
problems in scenarios where one wants to store the source in a type and
reference `self` in the `onTermination` closure at the same time; hence, I kept
the current pattern of setting the `onTermination` closure on the source.

### Provide a `onConsumerCancellation` callback

During the pitch phase, it was raised that we should provide a
`onConsumerCancellation` callback which gets invoked once the asynchronous
channel notices that the consuming task got cancelled. This callback could be
used to customize how cancellation is handled by the channel, e.g. one could
imagine writing a few more elements to the channel before finishing it. Right now,
the channel immediately returns `nil` or throws a `CancellationError` when it
notices cancellation. This proposal decided not to provide this customization
because it opens up the possibility that asynchronous channels are not terminating
when implemented incorrectly. Additionally, asynchronous sequences are not the
only place where task cancellation leads to an immediate error being thrown i.e.
`Task.sleep()` does the same. Hence, the value of the asynchronous not
terminating immediately brings little value when the next call in the iterating
task might throw. However, the implementation is flexible enough to add this in
the future, and we can just default it to the current behaviour.

### Create a custom type for the `Result` of the `onProduceMore` callback

The `onProducerMore` callback takes a `Result<Void, Error>` which is used to
indicate if the producer should produce more or if the asynchronous channel
finished. We could introduce a new type for this, but the proposal decided
against it since it effectively is a result type.

### Use an initializer instead of factory methods

Instead of providing a `makeChannel` factory method, we could use an initializer
approach that takes a closure which gets the `Source` passed into. A similar API
has been offered with the `Continuation` based approach and
[SE-0388](https://github.com/apple/swift-evolution/blob/main/proposals/0388-async-stream-factory.md)
introduced new factory methods to solve some of the usability ergonomics with
the initializer based APIs.

### Provide the type on older compilers

To achieve maximum performance, the implementation is using `~Copyable` extensively.
On Swift versions before 6.1, there is a https://github.com/swiftlang/swift/issues/78048 when using; hence, this type
is only usable with Swift 6.1 and later compilers. 

## Acknowledgements

- [Johannes Weiss](https://github.com/weissi) - For making me aware how
important this problem is and providing great ideas on how to shape the API.
- [Philippe Hausler](https://github.com/phausler) - For helping me designing the
APIs and continuously providing feedback
- [George Barnett](https://github.com/glbrntt) - For providing extensive code
reviews and testing the implementation.
- [Si Beaumont](https://github.com/simonjbeaumont) - For implementing the element size dependent strategy

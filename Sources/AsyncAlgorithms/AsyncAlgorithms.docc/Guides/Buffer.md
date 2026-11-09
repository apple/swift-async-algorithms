# Buffer

* Author(s): [Thibault Wittemberg](https://github.com/twittemb)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Buffer/AsyncBufferSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestBuffer.swift)
]

## Introduction

An `AsyncSequence` iterates in lock step with its consumer: the base sequence is only asked for the next element once the consumer has finished handling the previous one. That back pressure is usually desirable, but it means a slow consumer also slows down the production of elements. When the producer is time sensitive — a timer, a socket, a stream of notifications — the values that arrive while the consumer is busy should be kept for later rather than delaying the producer.

## Proposed Solution

A `buffer(policy:)` method is available on any `Sendable` `AsyncSequence`. It returns an asynchronous sequence that consumes the base sequence in a separate task, storing the elements it receives until the consumer is ready for them.

```swift
extension AsyncSequence where Self: Sendable {
  public func buffer(
    policy: AsyncBufferSequencePolicy
  ) -> AsyncBufferSequence<Self>
}
```

The policy determines what happens when elements are produced faster than they are consumed.

```swift
public struct AsyncBufferSequencePolicy: Sendable {
  public static func bounded(_ limit: Int) -> Self
  public static var unbounded: Self { get }
  public static func bufferingLatest(_ limit: Int) -> Self
  public static func bufferingOldest(_ limit: Int) -> Self
}
```

- `bounded(_:)` buffers up to `limit` elements and then suspends the iteration of the base sequence until the consumer drains the buffer. No element is ever discarded, and back pressure is preserved beyond the limit.
- `unbounded` buffers every element produced by the base sequence. No element is discarded and the base sequence is never suspended, so memory usage is bounded only by how far the consumer falls behind.
- `bufferingLatest(_:)` keeps the `limit` most recent elements. Once the buffer is full, the oldest buffered element is discarded to make room for the newly produced one.
- `bufferingOldest(_:)` keeps the `limit` first elements. Once the buffer is full, newly produced elements are discarded.

Passing a limit of `0` to any of the limited policies disables buffering entirely: the resulting sequence iterates the base sequence directly, exactly as if `buffer(policy:)` had not been applied.

## Detailed Design

```swift
public struct AsyncBufferSequence<Base: AsyncSequence & Sendable>: AsyncSequence {
  public typealias Element = Base.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

extension AsyncBufferSequence: Sendable where Base: Sendable { }

@available(*, unavailable)
extension AsyncBufferSequence.Iterator: Sendable { }
```

The base sequence is only iterated once a consumer asks for the first element; the task that drains it is created lazily by the first call to `next()`. When the base sequence finishes, the remaining buffered elements are still delivered to the consumer before the buffered sequence itself finishes.

When the base sequence throws, the failure is delivered in the order it was produced: elements already buffered ahead of the failure are emitted first, and the error is thrown afterwards. As with any throwing base sequence, iteration terminates at that point. `AsyncBufferSequence` rethrows, so buffering a non-throwing sequence produces a non-throwing sequence.

Cancelling the consuming task also terminates the iteration of the base sequence.

## Effect on API resilience

This is an additive API.

## Credits/Inspiration

The buffering policies are shaped after the `AsyncStream.Continuation.BufferingPolicy` type from the standard library, extended with the `bounded(_:)` case that preserves back pressure instead of discarding elements.

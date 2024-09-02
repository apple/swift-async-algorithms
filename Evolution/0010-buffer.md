# Buffer

* Proposal: [SAA-0010](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0010-buffer.md)
* Author(s): [Thibault Wittemberg](https://github.com/twittemb)
* Status: **Accepted**
* Implementation: [
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Buffer/AsyncBufferSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestBuffer.swift)
]
* Decision Notes:
* Bugs:

## Introduction

Buffering is a technique that balances supply and demand by temporarily storing elements to even out fluctuations in production and consumption rates. `AsyncStream` facilitates this process by allowing you to control the size of the buffer and the strategy for handling elements that exceed that size. However, this approach may not be suitable for all situations, and it doesn't provide a way to adapt other `AsyncSequence` types to incorporate buffering.

This proposal presents a new type that addresses these more advanced requirements and offers a comprehensive solution for buffering in asynchronous sequences.

## Motivation

As an `AsyncSequence` operates as a pull system, the production of elements is directly tied to the demand expressed by the consumer. The slower the consumer is in requesting elements, the slower the production of these elements will be. This can negatively impact the software that produces the elements, as demonstrated in the following example.

Consider an `AsyncSequence` that reads and returns a line from a file every time a new element is requested. To ensure exclusive access to the file, a lock is maintained while reading. Ideally, the lock should be held for as short a duration as possible to allow other processes to access the file. However, if the consumer is slow in processing received lines or has a fluctuating pace, the lock will be maintained for an extended period, reducing the performance of the system.

To mitigate this issue, a buffer operator can be employed to streamline the consumption of the `AsyncSequence`. This operator allows an internal iteration of the `AsyncSequence` independently from the consumer. Each element would then be made available for consumption by using a queuing mechanism.

By applying the buffer operator to the previous example, the file can be read as efficiently as possible, allowing the lock to be released in a timely manner. This results in improved performance, as the consumer can consume elements at its own pace without negatively affecting the system. The buffer operator ensures that the production of elements is not limited by the pace of the consumer, allowing both the producer and consumer to operate at optimal levels.

## Proposed Solution

We propose to extend `AsyncSequence` with a `buffer()` operator. This operator will return an `AsyncBufferSequence` that wraps the source `AsyncSequence` and handle the buffering mechanism.

This operator will accept an `AsyncBufferSequencePolicy`. The policy will dictate the behaviour in case of a buffer overflow.

As of now we propose 4 different behaviours:

```swift
public struct AsyncBufferSequencePolicy: Sendable {
  public static func bounded(_ limit: Int)
  public static var unbounded
  public static func bufferingLatest(_ limit: Int)
  public static func bufferingOldest(_ limit: Int)
}
``` 

And the public API of `AsyncBufferSequence` will be:

```swift
extension AsyncSequence where Self: Sendable {
  public func buffer(
    policy: AsyncBufferSequencePolicy
  ) -> AsyncBufferSequence<Self> {
    AsyncBufferSequence<Self>(base: self, policy: policy)
  }
}

public struct AsyncBufferSequence<Base: AsyncSequence & Sendable>: AsyncSequence {
  public typealias Element = Base.Element

  public func makeAsyncIterator() -> Iterator

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }
}

extension AsyncBufferSequence: Sendable where Base: Sendable { }
```

## Notes on Sendable

Since all buffering means that the base asynchronous sequence must be iterated independently of the consumption (to resolve the production versus consumption issue) the base `AsyncSequence` needs to be able to be sent across task boundaries (the iterator does not need this requirement).

## Detailed Design

The choice of the buffering policy is made through an enumeration whose values are related to a storage type. To date, two types of storage are implemented:

- `BoundedBufferStorage` backing the `AsyncBufferSequencePolicy.bounded(_:)` policy,
- `UnboundedBufferStorage` backing the `AsyncBufferSequencePolicy.unbounded`, `AsyncBufferSequencePolicy.bufferingNewest(_:)` and `AsyncBufferSequencePolicy.bufferingLatest(_:)` policies.

Both storage types rely on a Mealy state machine stored in a `ManagedCriticalState`. They drive the mutations of the internal buffer, while ensuring that concurrent access to the state are safe.

### BoundedBufferStorage

`BoundedBufferStorage` is instantiated with the upstream `AsyncSequence` and a buffer maximum size. Upon the first call to the `next()` method, a task is spawned to support the iteration over this `AsyncSequence`. The iteration  retrieves elements and adds them to an internal buffer as long as the buffer limit has not been reached. Meanwhile, the downstream `AsyncSequence` can access and consume these elements from the buffer. If the rate of consumption is slower than the rate of production, the buffer will eventually become full. In this case, the iteration is temporarily suspended until additional space becomes available.

### UnboundedBufferStorage

`UnboundedBufferStorage` is instantiated with the upstream `AsyncSequence` and a buffering policy. Upon the first call to the `next()` method, a task is spawned to support the iteration over this `AsyncSequence`. 

From there the behaviour will depend on the buffering policy.

#### Unbounded
If the policy is `unbounded`, the iteration retrieves elements and adds them to an internal buffer until the upstream `AsyncSequence` finishes or fails. Meanwhile, the downstream `AsyncSequence` can access and consume these elements from the buffer.

#### BufferingLatest
If the policy is `bufferingLatest(_:)`, the iteration retrieves elements and adds them to an internal buffer. Meanwhile, the downstream `AsyncSequence` can access and consume these elements from the buffer. If the rate of consumption is slower than the rate of production, the buffer will eventually become full. In this case the oldest buffered elements will be removed from the buffer and the latest ones will be added.

#### BufferingOldest
If the policy is `bufferingOldest(_:)`, the iteration retrieves elements and adds them to an internal buffer. Meanwhile, the downstream `AsyncSequence` can access and consume these elements from the buffer. If the rate of consumption is slower than the rate of production, the buffer will eventually become full. In this case the latest element will be discarded and never added to the buffer.

### Terminal events and cancellation

Terminal events from the upstream `AsyncSequence`, such as normal completion or failure, are delayed, ensuring that the consumer will receive all the elements before receiving the termination.

If the consuming `Task` is cancelled, so will be the `Task` supporting the iteration of the upstream `AsyncSequence`.

## Alternatives Considered

The buffering mechanism was originally thought to rely on an open implementation of an `AsyncBuffer` protocol, which would be constrained to an `Actor` conformance. It was meant for developers to be able to provide their own implementation of a buffering algorithm. This buffer was designed to control the behavior of elements when pushed and popped, in an isolated manner.

A default implementation was provided to offers a queuing strategy for buffering elements, with options for unbounded, oldest-first, or newest-first buffering.

This implementation was eventually discarded due to the potentially higher cost of calling isolated functions on an `Actor`, compared to using a low-level locking mechanism like the one employed in other operators through the use of the `ManagedCriticalState`.

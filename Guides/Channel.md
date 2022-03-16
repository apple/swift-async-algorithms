# Channel

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChannel.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncThrowingChannel.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestChannel.swift)
]

## Introduction

`AsyncStream` introduced a mechanism to send buffered elements from a context that doesn't use Swift concurrency into one that does. That design only addressed a portion of the potential use cases; the missing portion was the back pressure excerpted across two concurrency domains. 

## Proposed Solution

To achieve a system that supports back pressure and allows for the communication of more than one value from one task to another we are introducing a new type, the _channel_. The channel will be a reference-type asynchronous sequence with an asynchronous sending capability that awaits the consumption of iteration. Each value sent by the channel, or finish transmitted, will await the consumption of that value or event by iteration. That awaiting behavior will allow for the affordance of back pressure applied from the consumption site to be transmitted to the production site. This means that the rate of production cannot exceed the rate of consumption, and that the rate of consumption cannot exceed the rate of production.

## Detailed Design

Similar to the `AsyncStream` and `AsyncThrowingStream` types, the type for sending events via back pressure will come in two versions. These two versions will account for the throwing nature or non-throwing nature of the events being produced. 

Each type will have functions to send events and functions to send terminal events. 

```swift
public final class AsyncChannel<Element: Sendable>: AsyncSequence, Sendable {
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public mutating func next() async -> Element?
  }
  
  public init(element elementType: Element.Type = Element.self)
  
  public func send(_ element: Element) async
  public func finish() async
  
  public func makeAsyncIterator() -> Iterator
}

public final class AsyncThrowingChannel<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public mutating func next() async throws -> Element?
  }
  
  public init(element elementType: Element.Type = Element.self, failure failureType: Failure.Type = Failure.self)
  
  public func send(_ element: Element) async
  public func fail(_ error: Error) async where Failure == Error
  public func finish() async
  
  public func makeAsyncIterator() -> Iterator
}
```

## Alternatives Considered

The use of the name "subject" was considered, due to its heritage as a name for a sync-to-async adapter type.

## Credits/Inspiration

# Channel

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Channels/AsyncChannel.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Channels/AsyncThrowingChannel.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestChannel.swift)
]

## Introduction

`AsyncStream` introduced a mechanism to send buffered elements from a context that doesn't use Swift concurrency into one that does. That design only addressed a portion of the potential use cases; the missing portion was the back pressure excerpted across two concurrency domains. 

## Proposed Solution

To achieve a system that supports back pressure and allows for the communication of more than one value from one task to another we are introducing a new type, the _channel_. The channel will be a reference-type asynchronous sequence with an asynchronous sending capability that awaits the consumption of iteration. Each value sent by the channel will await the consumption of that value by iteration. That awaiting behavior will allow for the affordance of back pressure applied from the consumption site to be transmitted to the production site. This means that the rate of production cannot exceed the rate of consumption, and that the rate of consumption cannot exceed the rate of production. Sending a terminal event to the channel will instantly resume all pending operations for every producers and consumers.

## Detailed Design

Similar to the `AsyncStream` and `AsyncThrowingStream` types, the type for sending elements via back pressure will come in two versions. These two versions will account for the throwing nature or non-throwing nature of the elements being produced. 

Each type will have functions to send elements and to send terminal events. 

```swift
public final class AsyncChannel<Element: Sendable>: AsyncSequence, Sendable {
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public mutating func next() async -> Element?
  }
  
  public init(element elementType: Element.Type = Element.self)
  
  public func send(_ element: Element) async
  public func finish()
  
  public func makeAsyncIterator() -> Iterator
}

public final class AsyncThrowingChannel<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public mutating func next() async throws -> Element?
  }
  
  public init(element elementType: Element.Type = Element.self, failure failureType: Failure.Type = Failure.self)
  
  public func send(_ element: Element) async
  public func fail(_ error: Error) where Failure == Error
  public func finish()
  
  public func makeAsyncIterator() -> Iterator
}
```

Channels are intended to be used as communication types between tasks. Particularly when one task produces values and another task consumes said values. On the one hand, the back pressure applied by `send(_:)` via the suspension/resume ensures that the production of values does not exceed the consumption of values from iteration. This method suspends after enqueuing the event and is resumed when the next call to `next()` on the `Iterator` is made. On the other hand, the call to `finish()` or `fail(_:)` immediately resumes all the pending operations for every producers and consumers. Thus, every suspended `send(_:)` operations instantly resume, so as every suspended `next()` operations by producing a nil value, or by throwing an error, indicating the termination of the iterations. Further calls to `send(_:)` will immediately resume. The calls to `send(:)` and `next()` will immediately resume when their supporting task is cancelled, other operations from other tasks will remain active.

```swift
let channel = AsyncChannel<String>()
Task {
  while let resultOfLongCalculation = doLongCalculations() {
    await channel.send(resultOfLongCalculation)
  }
  channel.finish()
}

for await calculationResult in channel {
  print(calculationResult)
}
```

The example above uses a task to perform intense calculations; each of which are sent to the other task via the `send(_:)` method. That call to `send(_:)` returns when the next iteration of the channel is invoked. 

## Alternatives Considered

The use of the name "subject" was considered, due to its heritage as a name for a sync-to-async adapter type.

It was considered to make `AsyncChannel` and `AsyncThrowingChannel` actors, however due to the cancellation internals it would imply that these types would need to create new tasks to handle cancel events. The advantages of an actor in this particular case did not outweigh the impact of adjusting the implementations to be actors.

## Credits/Inspiration

`AsyncChannel` and `AsyncThrowingChannel` was heavily inspired from `Subject` but with the key difference that it uses Swift concurrency to apply back pressure.

https://developer.apple.com/documentation/combine/subject/

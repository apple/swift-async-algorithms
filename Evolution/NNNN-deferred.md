# Deferred

* Proposal: [NNNN](NNNN-deferred.md)
* Authors: [Tristan Celder](https://github.com/tcldr)
* Review Manager: TBD
* Status: **Awaiting implementation**

* Implementation: [[Source](https://github.com/tcldr/swift-async-algorithms/blob/pr/deferred/Sources/AsyncAlgorithms/AsyncDeferredSequence.swift) | 
[Tests](https://github.com/tcldr/swift-async-algorithms/blob/pr/deferred/Tests/AsyncAlgorithmsTests/TestDeferred.swift)]
* Decision Notes: [Additional Commentary](https://forums.swift.org/)
* Bugs:

## Introduction

`AsyncDeferredSequence` provides a convenient way to postpone the initialization of a sequence to the point where it is requested by a sequence consumer. 

## Motivation

Some source sequences may perform expensive work on initialization. This could be network activity, sensor activity, or anything else that consumes system resources. While this can be mitigated in some simple situtations by only passing around a sequence at the point of use, often it is favorable to be able to pass a sequence to its eventual point of use without commencing its initialization process. This is especially true for sequences which are intended for multicast/broadcast for which a reliable startup and shutdown procedure is essential.

A simple example of a seqeunce which may benefit from being deferred is provided in the documentation for AsyncStream:

```swift
extension QuakeMonitor {

    static var quakes: AsyncStream<Quake> {
        AsyncStream { continuation in
            let monitor = QuakeMonitor()
            monitor.quakeHandler = { quake in
                continuation.yield(quake)
            }
            continuation.onTermination = { @Sendable _ in
                 monitor.stopMonitoring()
            }
            monitor.startMonitoring()
        }
    }
}
```

In the supplied code sample, the closure provided to the AsyncStream initializer will be executed immediately upon initialization; `QuakeMonitor.startMonitoring()` will be called, and the stream will then begin buffering its contents waiting to be iterated. Whilst this behavior is sometimes desirable, on other occasions it can cause system resources to be consumed unnecessarily.

```swift
let nonDeferredSequence = QuakeMonitor.quakes //  `Quake.startMonitoring()` is called now!

...
// at some arbitrary point, possibly hours later...
for await quake in nonDeferredSequence {
    print("Quake: \(quake.date)")
}
// Prints out hours of previously buffered quake data before showing the latest
```

## Proposed solution

`AsyncDeferredSequence` uses a supplied closure to create a new asynchronous sequence. The closure is executed for each iterator on the first call to `next`. This has the effect of postponing the initialization of an arbitrary async sequence until the point of first demand:

```swift
let deferredSequence = deferred(QuakeMonitor.quakes) // Now, initialization is postponed

...
// at some arbitrary point, possibly hours later...
for await quake in deferredSequence {  //  `Quake.startMonitoring()` is now called
    print("Quake: \(quake.date)")
}
// Prints out only the latest quake data
```

Now, potentially expensive system resources are consumed only at the point they're needed.

## Detailed design

`AsyncDeferredSequence` is a trivial algorithm supported by some convenience functions.

### Functions

```swift
public func deferred<Base>(
  _ createSequence: @escaping @Sendable () async -> Base
) -> AsyncDeferredSequence<Base> where Base: AsyncSequence, Base: Sendable

public func deferred<Base: AsyncSequence & Sendable>(
  _ createSequence: @autoclosure @escaping @Sendable () -> Base
) -> AsyncDeferredSequence<Base> where Base: AsyncSequence, Base: Sendable
```

The synchronous function can be auto-escaped, simplifying the call-site. While the async variant allows a sequence to be initialized within a concurrency context other than that of the end consumer.

```swift
public struct AsyncDeferredSequence<Base> where Base: AsyncSequence, Base: Sendable {
  public typealias Element = Base.Element
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }
  public func makeAsyncIterator() -> Iterator
}
```

### Naming

The `deferred(_:)` function takes its inspiration from the Combine publisher of the same name with similar functionality. However, `lazy(_:)` could be quite fitting, too.

### Comparison with other libraries

**ReactiveX** ReactiveX has an [API definition of Defer](https://reactivex.io/documentation/operators/defer.html) as a top level operator for generating observables.

**Combine** Combine has an [API definition of Deferred](https://developer.apple.com/documentation/combine/deferred) as a top-level convenience publisher.


## Effect on API resilience

Deferred has a trivial implementation and is marked as `@frozen` and `@inlinable`. This removes the ability of this type and functions to be ABI resilient boundaries at the benefit of being highly optimizable.

## Alternatives considered

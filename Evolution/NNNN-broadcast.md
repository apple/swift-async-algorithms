# Broadcast

* Proposal: [NNNN](NNNN-broadcast.md)
* Authors: [Tristan Celder](https://github.com/tcldr)
* Review Manager: TBD
* Status: **Awaiting implementation**


 * Implementation: [[Source](https://github.com/tcldr/swift-async-algorithms/blob/pr/share/Sources/AsyncAlgorithms/AsyncBroadcastSequence.swift) |
 [Tests](https://github.com/tcldr/swift-async-algorithms/blob/pr/share/Tests/AsyncAlgorithmsTests/TestBroadcast.swift)]

## Introduction

`AsyncBroadcastSequence` unlocks additional use cases for structured concurrency and asynchronous sequences by allowing almost any asynchronous sequence to be adapted for consumption by multiple concurrent consumers.

## Motivation

The need often arises to distribute the values of an asynchronous sequence to multiple consumers. Intuitively, it seems that a sequence _should_ be iterable by more than a single consumer, but many types of asynchronous sequence are restricted to supporting only one consumer at a time.

One example of an asynchronous sequence that would naturally fit this 'one to many' shape is the output of a hardware sensor. A hypothetical hardware sensor might include the following API:

```swift
public final class Accelerometer {
  
  public struct Event { /* ... */ }
  
  // exposed as a singleton to represent the single on-device sensor
  public static let shared = Accelerometer()
  
  private init() {}
  
  public var updateHandler: ((Event) -> Void)?
  
  public func startAccelerometer() { /* ... */ }
  public func stopAccelerometer() { /* ... */ }
}
```

To share the sensor data with a consumer through an asynchronous sequence you might choose an `AsyncStream`:

```swift
final class OrientationMonitor { /* ... */ }
extension OrientationMonitor {
  
  static var orientation: AsyncStream<Accelerometer.Event> {
    AsyncStream { continuation in
      Accelerometer.shared.updateHandler = { event in
        continuation.yield(event)
      }
      continuation.onTermination = { @Sendable _ in
        Accelerometer.shared.stopAccelerometer()
      }
      Accelerometer.shared.startAccelerometer()
    }
  }
}
```

With a single consumer, this pattern works as expected:

```swift
let consumer1 = Task {
  for await orientation in OrientationMonitor.orientation {
      print("Consumer 1: Orientation: \(orientation)")
  }
}
// Output:
// Consumer 1: Orientation: (0.0, 1.0, 0.0)
// Consumer 1: Orientation: (0.0, 0.8, 0.0)
// Consumer 1: Orientation: (0.0, 0.6, 0.0)
// Consumer 1: Orientation: (0.0, 0.4, 0.0)
// ...
```

However, as soon as a second consumer comes along, data for the first consumer stops. This is because the singleton `Accelerometer.shared.updateHandler` is updated within the closure for the creation of the second `AsyncStream`. This has the effect of redirecting all Accelerometer data to the second stream.

One attempted workaround might be to vend a single `AsyncStream` to all consumers:

```swift
extension OrientationMonitor {
  
  static let orientation: AsyncStream<Accelerometer.Event> = {
    AsyncStream { continuation in
      Accelerometer.shared.updateHandler = { event in
        continuation.yield(event)
      }
      continuation.onTermination = { @Sendable _ in
        Accelerometer.shared.stopAccelerometer()
      }
      Accelerometer.shared.startAccelerometer()
    }
  }()
}
```

This comes with another issue though: when two consumers materialise, the output of the stream becomes split between them:

```swift
let consumer1 = Task {
  for await orientation in OrientationMonitor.orientation {
      print("Consumer 1: Orientation: \(orientation)")
  }
}
let consumer2 = Task {
  for await orientation in OrientationMonitor.orientation {
      print("Consumer 2: Orientation: \(orientation)")
  }
}
// Output:
// Consumer 1: Orientation: (0.0, 1.0, 0.0)
// Consumer 2: Orientation: (0.0, 0.8, 0.0)
// Consumer 2: Orientation: (0.0, 0.6, 0.0)
// Consumer 1: Orientation: (0.0, 0.4, 0.0)
// ...
``` 
Rather than consumers receiving all values emitted by the `AsyncStream`, they receive only a subset. In addition, if the task of a consumer is cancelled, via `consumer2.cancel()` for example, the `onTermination` trigger of the `AsyncSteam.Continuation` executes and stops Accelerometer data being generated for _both_ tasks.

## Proposed solution

`AsyncBroadcastSequence` provides a way to multicast a single upstream asynchronous sequence to any number of consumers.

```
extension OrientationMonitor {
  
  static let orientation: AsyncBroadcastSequence<AsyncStream<Accelerometer.Event>> = {
    let stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      Accelerometer.shared.updateHandler = { event in
        continuation.yield(event)
      }
      Accelerometer.shared.startAccelerometer()
    }
    return stream.share(disposingBaseIterator: .whenTerminated)
  }()
}
```

Now, each consumer receives every element output by the source stream:

```swift
let consumer1 = Task {
  for await orientation in OrientationMonitor.orientation {
      print("Consumer 1: Orientation: \(orientation)")
  }
}
let consumer2 = Task {
  for await orientation in OrientationMonitor.orientation {
      print("Consumer 2: Orientation: \(orientation)")
  }
}
// Output:
// Consumer 1: Orientation: (0.0, 1.0, 0.0)
// Consumer 2: Orientation: (0.0, 1.0, 0.0)
// Consumer 1: Orientation: (0.0, 0.8, 0.0)
// Consumer 2: Orientation: (0.0, 0.8, 0.0)
// Consumer 1: Orientation: (0.0, 0.6, 0.0)
// Consumer 2: Orientation: (0.0, 0.6, 0.0)
// Consumer 1: Orientation: (0.0, 0.4, 0.0)
// Consumer 2: Orientation: (0.0, 0.4, 0.0)
// ...
```

This does leave our accelerometer running even when the last consumer has cancelled though. While this makes sense for some use-cases, it would be better if we could automate shutdown of the accelerometer when there's no longer any demand, and start it up again when demand returns. With the help of the `deferred` algorithm, we can:

```swift
extension OrientationMonitor {
  
  static let orientation: AsyncBroadcastSequence<AsyncDeferredSequence<AsyncStream<Accelerometer.Event>>> = {
    let stream = deferred {
      AsyncStream { continuation in
        Accelerometer.shared.updateHandler = { event in
          continuation.yield(event)
        }
        continuation.onTermination = { @Sendable _ in
          Accelerometer.shared.stopAccelerometer()
        }
        Accelerometer.shared.startAccelerometer()
      }
    }
    // `.whenTerminatedOrVacant` is the default, so we could equally write `.share()`
    // but it's included here for clarity.
    return stream.share(disposingBaseIterator: .whenTerminatedOrVacant)
  }()
}
```

With `.whenTerminatedOrVacant` set as the iterator disposal policy (the default), when the last downstream consumer cancels the upstream iterator is dropped. This triggers `AsyncStream`'s `onTermination` handler, shutting off the Accelerometer.

Now, with `AsyncStream` composed with `AsyncDeferredSequence`, any new demand triggers the re-execution of `AsyncDeferredSequence`'s' closure, the restart of the Accelerometer, and a new sequence for `AsyncBroadcastSequence` to share.

### Configuration Options

`AsyncBroadcastSequence` provides two conveniences to adapt the sequence for the most common multicast use-cases:
  1. As described above, a configurable iterator disposal policy that determines whether the shared upstream iterator is disposed of when the consumer count count falls to zero.
  2. A history feature that allows late-coming consumers to receive the most recently emitted elements prior to their arrival. One use-case could be a UI that is updated by an infrequently emitting sequence. Rather than wait for the sequence to emit a new element to populate an interface, the last emitted value can be used until such time that fresh data is emitted.

## Detailed design

### Algorithm Summary:
The idea behind the `AsyncBroadcastSequence` algorithm is as follows: Vended iterators of `AsyncBroadcastSequence` are known as 'runners'. Runners compete in a race to grab the next element from a base iterator for each of its iteration cycles. The 'winner' of an iteration cycle returns the element to the shared context which then supplies the result to later finishers. Once every runner has finished, the current cycle completes and the next iteration can start. This means that runners move forward in lock-step, only proceeding when the the last runner in the current iteration has received a value or has cancelled.

#### `AsyncBroadcastSequence` Iterator Lifecycle:

  1. **Connection**: On connection, each 'runner' is issued with an ID (and any prefixed values from the history buffer) by the shared context. From this point on, the algorithm will wait on this iterator to consume its values before moving on. This means that until `next()` is called on this iterator, all the other iterators will be held until such time that it is, or the iterator's task is cancelled.
  2. **Run**: After its prefix values have been exhausted, each time `next()` is called on the iterator, the iterator attempts to start a 'run' by calling `startRun(_:)` on the shared context. The shared context marks the iterator as 'running' and issues a role to determine the iterator's action for the current iteration cycle. The roles are as follows:
    - **FETCH**: The iterator is the 'winner' of this iteration cycle. It is issued with the shared base iterator, calls `next()` on it, and once it resumes returns the value to the shared context.
    - **WAIT**: The iterator hasn't won this cycle, but was fast enough that the winner has yet to resume with the element from the base iterator. Therefore, it is told to suspend (WAIT) until such time that the winner resumes.
    - **YIELD**: The iterator is late (and is holding up the other iterators). The shared context issues it with the value retrieved by the winning iterator and lets it continue immediately.
    - **HOLD**: The iterator is early for the next iteration cycle. So it is put in the holding pen until the next cycle can start. This is because there are other iterators that still haven't finished their run for the current iteration cycle. This iterator will be resumed when all other iterators have completed their run.
    
  3. **Completion**: The iterator calls cancel on the shared context which ensures the iterator does not take part in the next iteration cycle. However, if it is currently suspended it may not resume until the current iteration cycle concludes. This is especially important if it is filling the key FETCH role for the current iteration cycle.

### AsyncBroadcastSequence

#### Declaration

```swift
public struct AsyncBroadcastSequence<Base: AsyncSequence> where Base: Sendable, Base.Element: Sendable
```

#### Overview

An asynchronous sequence that can be iterated by multiple concurrent consumers.

Use an asynchronous broadcast sequence when you have multiple downstream asynchronous sequences with which you wish to share the output of a single asynchronous sequence. This can be useful if you have expensive upstream operations, or if your asynchronous sequence represents the output of a physical device.

Elements are emitted from an asynchronous broadcast sequence at a rate that does not exceed the consumption of its slowest consumer. If this kind of back-pressure isn't desirable for your use-case, `AsyncBroadcastSequence` can be composed with buffers – either upstream, downstream, or both – to acheive the desired behavior.

If you have an asynchronous sequence that consumes expensive system resources, it is possible to configure `AsyncBroadcastSequence` to discard its upstream iterator when the connected downstream consumer count falls to zero. This allows any cancellation tasks configured on the upstream asynchronous sequence to be initiated and for expensive resources to be terminated. `AsyncBroadcastSequence` will re-create a fresh iterator if there is further demand.

For use-cases where it is important for consumers to have a record of elements emitted prior to their connection, a `AsyncBroadcastSequence` can also be configured to prefix its output with the most recently emitted elements. If `AsyncBroadcastSequence` is configured to drop its iterator when the connected consumer count falls to zero, its history will be discarded at the same time.

#### Creating a sequence

```
init(
  _ base: Base,
  history historyCount: Int = 0,
  disposingBaseIterator iteratorDisposalPolicy: IteratorDisposalPolicy = .whenTerminatedOrVacant
)
```

Contructs a shared asynchronous sequence.

  - `history`: the number of elements previously emitted by the sequence to prefix to the iterator of a new consumer
  - `iteratorDisposalPolicy`: the iterator disposal policy applied to the upstream iterator

### AsyncBroadcastSequence.IteratorDisposalPolicy

#### Declaration

```swift
public enum IteratorDisposalPolicy: Sendable {
  case whenTerminated
  case whenTerminatedOrVacant
}
```

#### Overview
The iterator disposal policy applied by a shared asynchronous sequence to its upstream iterator

  - `whenTerminated`: retains the upstream iterator for use by future consumers until the base asynchronous sequence is terminated
  - `whenTerminatedOrVacant`: discards the upstream iterator when the number of consumers falls to zero or the base asynchronous sequence is terminated

### broadcast(history:disposingBaseIterator)

#### Declaration

```swift
extension AsyncSequence {

  public func broadcast(
    history historyCount: Int = 0,
    disposingBaseIterator iteratorDisposalPolicy: AsyncBroadcastSequence<Self>.IteratorDisposalPolicy = .whenTerminatedOrVacant
  ) -> AsyncBroadcastSequence<Self>
}
```

#### Overview

Creates an asynchronous sequence that can be shared by multiple consumers.

  - `history`: the number of elements previously emitted by the sequence to prefix to the iterator of a new consumer
  - `iteratorDisposalPolicy`: the iterator disposal policy applied by a shared asynchronous sequence to its upstream iterator

 ## Comparison with other libraries

   - **ReactiveX** ReactiveX has the [Publish](https://reactivex.io/documentation/operators/publish.html) observable which when can be composed with the [Connect](https://reactivex.io/documentation/operators/connect.html), [RefCount](https://reactivex.io/documentation/operators/refcount.html) and [Replay](https://reactivex.io/documentation/operators/replay.html) operators to support various multi-casting use-cases. The `discardsBaseIterator` behavior is applied via `RefCount` (or the .`share().refCount()` chain of operators in RxSwift), while the history behavior is achieved through `Replay` (or the .`share(replay:)` convenience in RxSwift)

   - **Combine** Combine has the [ multicast(_:)](https://developer.apple.com/documentation/combine/publishers/multicast) operator, which along with the functionality of [ConnectablePublisher](https://developer.apple.com/documentation/combine/connectablepublisher) and associated conveniences supports many of the same use cases as the ReactiveX equivalent, but in some instances requires third-party ooperators to achieve the same level of functionality.
 
Due to the way a Swift `AsyncSequence`, and therefore `AsyncBroadcastSequence`, naturally applies back-pressure, the characteristics of an `AsyncBroadcastSequence` are different enough that a one-to-one API mapping of other reactive programmming libraries isn't applicable.

However, with the available configuration options – and through composition with other asynchronous sequences – `AsyncBroadcastSequence` can trivially be adapted to support many of the same use-cases, including that of [Connect](https://reactivex.io/documentation/operators/connect.html), [RefCount](https://reactivex.io/documentation/operators/refcount.html), and [Replay](https://reactivex.io/documentation/operators/replay.html).

 ## Effect on API resilience

TBD

## Alternatives considered

Creating a one-to-one multicast analog that matches that of existing reactive programming libraries. However, it would mean fighting the back-pressure characteristics of `AsyncSequence`. Instead, this implementation embraces back-pressure to yield a more flexible result.

## Acknowledgments

Thanks to [Philippe Hausler](https://github.com/phausler) and [Franz Busch](https://github.com/FranzBusch), as well as all other contributors on the Swift forums, for their thoughts and feedback.

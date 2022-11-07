# Share

* Proposal: [NNNN](NNNN-deferred.md)
* Authors: [Tristan Celder](https://github.com/tcldr)
* Review Manager: TBD
* Status: **Awaiting implementation**


 * Implementation: [[Source](https://github.com/tcldr/swift-async-algorithms/blob/pr/share/Sources/AsyncAlgorithms/AsyncSharedSequence.swift) |
 [Tests](https://github.com/tcldr/swift-async-algorithms/blob/pr/share/Tests/AsyncAlgorithmsTests/TestShare.swift)]

## Introduction

`AsyncSharedSequence` unlocks additional use cases for structured concurrency and asynchronous sequences by allowing almost any asynchronous sequence to be adapted for consumption by multiple concurrent consumers.

## Motivation

The need often arises to distribute the values of an asynchronous sequence to multiple consumers. Intuitively, it seems that a sequence _should_ be iterable by more than a single consumer, but many types of asynchronous sequence are restricted to supporting only one consumer at a time.

## Proposed solution

`AsyncSharedSequence` lifts this restriction, providing a way to multicast a single upstream asynchronous sequence to any number of consumers.

It also provides two conveniences to adapt the sequence for the most common multicast use-cases:
  1. A history feature that allows late-coming consumers to receive the most recently emitted elements prior to their arrival.
  2. A configurable iterator disposal policy that determines whether the shared upstream iterator is disposed of when the consumer count count falls to zero.

## Detailed design

### AsyncSharedSequence

#### Declaration

```swift
public struct AsyncSharedSequence<Base: AsyncSequence> where Base: Sendable, Base.Element: Sendable
```

#### Overview

An asynchronous sequence that can be iterated by multiple concurrent consumers.

Use a shared asynchronous sequence when you have multiple downstream asynchronous sequences with which you wish to share the output of a single asynchronous sequence. This can be useful if you have expensive upstream operations, or if your asynchronous sequence represents the output of a physical device.

Elements are emitted from a multicast asynchronous sequence at a rate that does not exceed the consumption of its slowest consumer. If this kind of back-pressure isn't desirable for your use-case, `AsyncSharedSequence` can be composed with buffers – either upstream, downstream, or both – to acheive the desired behavior.

If you have an asynchronous sequence that consumes expensive system resources, it is possible to configure `AsyncSharedSequence` to discard its upstream iterator when the connected downstream consumer count falls to zero. This allows any cancellation tasks configured on the upstream asynchronous sequence to be initiated and for expensive resources to be terminated. `AsyncSharedSequence` will re-create a fresh iterator if there is further demand.

For use-cases where it is important for consumers to have a record of elements emitted prior to their connection, a `AsyncSharedSequence` can also be configured to prefix its output with the most recently emitted elements. If `AsyncSharedSequence` is configured to drop its iterator when the connected consumer count falls to zero, its history will be discarded at the same time.

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

### AsyncSharedSequence.IteratorDisposalPolicy

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

### share(history:disposingBaseIterator)

#### Declaration

```swift
extension AsyncSequence {

  public func share(
    history historyCount: Int = 0,
    disposingBaseIterator iteratorDisposalPolicy: AsyncSharedSequence<Self>.IteratorDisposalPolicy = .whenTerminatedOrVacant
  ) -> AsyncSharedSequence<Self>
}
```

#### Overview

Creates an asynchronous sequence that can be shared by multiple consumers.

  - `history`: the number of elements previously emitted by the sequence to prefix to the iterator of a new consumer
  - `iteratorDisposalPolicy`: the iterator disposal policy applied by a shared asynchronous sequence to its upstream iterator

## Naming

 The `share(history:disposingBaseIterator)` function takes its inspiration from the [`share()`](https://developer.apple.com/documentation/combine/fail/share()) Combine publisher, and the RxSwift [`share(replay:)`](https://github.com/ReactiveX/RxSwift/blob/3d3ed05bed71f19999db2207c714dab0028d37be/Documentation/GettingStarted.md#sharing-subscription-and-share-operator) operator, both of which fall under the multicasting family of operators in their respective libraries.

 ## Comparison with other libraries

   - **ReactiveX** ReactiveX has the [Publish](https://reactivex.io/documentation/operators/publish.html) observable which when can be composed with the [Connect](https://reactivex.io/documentation/operators/connect.html), [RefCount](https://reactivex.io/documentation/operators/refcount.html) and [Replay](https://reactivex.io/documentation/operators/replay.html) operators to support various multi-casting use-cases. The `discardsBaseIterator` behavior is applied via `RefCount` (or the .`share().refCount()` chain of operators in RxSwift), while the history behavior is achieved through `Replay` (or the .`share(replay:)` convenience in RxSwift)

   - **Combine** Combine has the [ multicast(_:)](https://developer.apple.com/documentation/combine/publishers/multicast) operator, which along with the functionality of [ConnectablePublisher](https://developer.apple.com/documentation/combine/connectablepublisher) and associated conveniences supports many of the same use cases as the ReactiveX equivalent, but in some instances requires third-party ooperators to achieve the same level of functionality.
 
Due to the way a Swift `AsyncSequence`, and therefore `AsyncSharedSequence`, naturally applies back-pressure, the characteristics of an `AsyncSharedSequence` are different enough that a one-to-one API mapping of other reactive programmming libraries isn't applicable.

However, with the available configuration options – and through composition with other asynchronous sequences – `AsyncSharedSequence` can trivially be adapted to support many of the same use-cases, including that of [Connect](https://reactivex.io/documentation/operators/connect.html), [RefCount](https://reactivex.io/documentation/operators/refcount.html), and [Replay](https://reactivex.io/documentation/operators/replay.html).

 ## Effect on API resilience

TBD

## Alternatives considered

Creating a one-to-one multicast analog that matches that of existing reactive programming libraries. However, it would mean fighting the back-pressure characteristics of `AsyncSequence`. Instead, this implementation embraces back-pressure to yield a more flexible result.

## Acknowledgments

Thanks to [Philippe Hausler](https://github.com/phausler) and [Franz Busch](https://github.com/FranzBusch), as well as all other contributors on the Swift forums, for their thoughts and feedback.

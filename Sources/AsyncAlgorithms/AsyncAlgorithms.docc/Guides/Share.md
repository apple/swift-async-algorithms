# Share

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncShareSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestShare.swift)
]

## Introduction

Many of the AsyncSequence adopting types only permit a one singular consumption. However there are many times that the same produced values are useful in more than one place. Out of that mechanism there are a few approaches to share, distribute, and broadcast those values. This proposal will focus on one concept; sharing. Sharing is where each consumption independently can make forward progress and  get the same values but do not replay from the beginning of time.

## Motivation

There are many potential usages for the sharing concept of AsyncSequences. 

One such example is the case where a source of data as an asynchronous sequence needs to be consumed by updating UI, logging, and additionally  a network connection. This particular case does not matter on which uses but instead that those uses are independent of each other. It would not be expected for networking to block or delay the updates to UI, nor should logging. This example case also illustrates that the isolation of each side might be different and that some of the sides may not tolerate coalescing or dropping values.

There are many other use cases that have been requested for this family of algorithms. Since the release of AsyncAlgorithms it has perhaps been the most popularly requested set of behaviors as additions to the package.

## Proposed solution

AsyncAlgorithms will introduce a new extension function on AsyncSequence that will provide a shareable asynchronous sequence that will produce the same values upon iteration from multiple instances of it's AsyncIterator. Those iterations can take place in multiple isolations.

When values from a differing isolation cannot be coalesced, the two options available are either awaiting (an exertion of back-pressure across the sequences) or buffering (an internal back-pressure to a buffer). Replaying the values from the beginning of the creation of the sequence is a distinctly different behavior that should be considered a different use case. This then leaves the behavioral characteristic of this particular operation of share as; sharing a buffer of values started from the initialization of a new iteration of the sequence. Control over that buffer should then have options to determine the behavior, similar to how AsyncStream allows that control. It should have options to be unbounded, buffering the oldest count of elements, or buffering the newest count of elements.

It is critical to identify that this is one algorithm in the family of algorithms for sharing values. It should not attempt to solve all behavioral requirements but instead serve a common set of them that make cohesive sense together. This proposal is not mutually exclusive to the other algorithms in the sharing family.

## Detailed design

A new extension will be added to return a `Sendable` `AsyncSequence`. This extension will take a buffering policy to identify how the buffer will be handled when iterations do not consume at the same rate.

The `Sendable` annotation identifies to the developer that this sequence can be shared and stored in an existental `any`.

```swift
extension AsyncSequence where Element: Sendable {
  public func share(
    bufferingPolicy: AsyncBufferSequencePolicy = .bounded(1)
  ) -> some AsyncSequence<Element, Failure> & Sendable
}
```

The buffer internally to the share algorithm will only extend back to the furthest element available but there will only be a singular buffer shared across all iterators. This ensures that with the application of the buffering policy the storage size is as minimal as possible while still allowing all iterations to avoid dropping values and keeping the memory usage in check. The signature reuses the existing `AsyncBufferSequencePolicy` type to specify the behavior around buffering either responding to how it should limit emitting to the buffer or what should happen when the buffer is exceeded.

## Runtime Behavior

The runtime behaviors fall into a few categories; ordering, iteration isolation, cancellation, and lifetimes. To understand the beahviors there are a terms useful to define. Each creation of the AsyncIterator of the sequence and invocation of next will be referred to a side of the share iteration. The back pressure to the system to fetch a new element or termination is refered to as demand. The limit which is the pending gate for awaiting until the buffer has been serviced used for the `AsyncBufferSequencePolicy.bounded(_ : Int)` policy. The last special definition is that of the extent which is specifically in this case the lifetime of the asynchronous sequence itself.

When the underlying type backing the share algorithm is constructed a new extent is created; this is used for tracking the reference lifetime under the hood and is used to both house the iteration but also to identify the point at which no more sides can be constructed. When no more sides can be constructed and no sides are left to iterate then the backing iteration is canceled. This prevents any un-referenced task backing the iteration to not be leaked by the algorith itself.

That construction then creates an initial shared state and buffer. No task is started initially; it is only upon the first demand that the task backing the iteration is started; this means on the first call to next a task is spun up servicing all potential sides. The order of which the sides are serviced is not specified and cannot be relied upon, however the order of delivery within a side is always guarenteed to be ordered. The singular task servicing the iteration will be the only place holding any sort of iterator from the base `AsyncSequence`; so that iterator is isolated and not sent from one isolation to another. That iteration first awaits any limit availability and then awaits for a demand given by a side. After-which it then awaits an element or terminal event from the iterator and enqueues the elements to the buffer. 

The buffer itself is only held in one location, each side however has a cursor index into that buffer and when values are consumed it adjusts the indexes accordingly; leaving the buffer usage only as big as the largest deficit. This means that new sides that are started post initial start up will not have a "replay" effect; that is a similar but distinct algorithm and is not addressed by this proposal. Any buffer size sensitive systems that wish to adjust behavior should be aware that specifying a policy is a suggested step. However in common usage similar to other such systems servicing desktop and mobile applications the common behavior is often unbounded. Alternatively desktop or mobile applications will often want `.bounded(1)` since that enforces the slowest consumption to drive the forward progress at most 1 buffered element. All of the use cases have a reasonable default of `.bounded(1)`; mobile, deskop, and server side uses. Leaving this as the default parameter keeps the progressive disclosure of the beahviors - such that the easiest thing to write is correct for all uses, and then more advanced control can be adjusted by passing in a specific policy. This default argument diverges slightly from AsyncStream, but follows a similar behavior to that of Combine's `share`.

As previously stated, the isolation of the iteration of the upstream/base AsyncSequence is to a detached task, this ensures that individual sides can have independent cancellation. Those cancellations will have the effect of remvoing that side from the shared iteration and cleaning up accordingly (including adjusting the trimming of the internal buffer).

Representing concurrent access is difficult to express all potential examples but there are a few cases included with this proposal to illustrate some of the behaviors. If a more comprehensive behavioral analysis is needed, it is strongly suggested to try out the pending pull request to identify how specific behaviors work. Please keep in mind that the odering between tasks is not specified, only the order within one side of iteration.

Practically this all means that a given iteration may be "behind" another and can eventually catch up (provided it is within the buffer limit).

```swift
let exampleSource = [0, 1, 2, 3, 4].async.share(bufferingPolicy: .unbounded)

let t1 = Task {
  for await element in exampleSource {
    if element == 0 {
      try? await Task.sleep(for: .seconds(1))
    }
    print("Task 1", element)
  }
}

let t2 = Task {
  for await element in exampleSource {
    if element == 3 {
      try? await Task.sleep(for: .seconds(1))
    }
    print("Task 2", element)
  }
}

await t1.value
await t2.value

```

This example will print a possible ordering of the following:

```
Task 2 0
Task 2 1
Task 2 2
Task 1 0
Task 2 3
Task 2 4
Task 1 1
Task 1 2
Task 1 3
Task 1 4
```

The order of the interleaving of the prints are not guaranteed; however the order of the elements per iteration is. Likewise in this buffering case it is guaranteed that all values are represented in the output.

If the creation were instead altered to the following:

```swift
let exampleSource = [0, 1, 2, 3, 4].async.share(bufferingPolicy: .bufferingLatest(2))
```

The output would print the possible ordering of:

```
Task 2 0
Task 2 1
Task 2 2
Task 1 0
Task 2 4
Task 1 3
Task 1 4
```

Some values are dropped due to the buffering policy, but eventually they reach consistency. Which similarly works for the following:

```
let exampleSource = [0, 1, 2, 3, 4].async.share(bufferingPolicy: .bufferingOldest(2))
```

```
Task 2 0
Task 2 1
Task 2 2
Task 1 0
Task 2 4
Task 1 1
Task 1 2
```

However in this particular case the newest values are the dropped elements.

The `.bounded(N)` policy enforces consumption to prevent any side from being beyond a given amount away from other sides' consumption.

```swift
let exampleSource = [0, 1, 2, 3, 4].async.share(bufferingPolicy: .bounded(1))

let t1 = Task {
  for await element in exampleSource {
    if element == 0 {
      try? await Task.sleep(for: .seconds(1))
    }
    print("Task 1", element)
  }
}

let t2 = Task {
  for await element in exampleSource {
    if element == 3 {
      try? await Task.sleep(for: .seconds(1))
    }
    print("Task 2", element)
  }
}

await t1.value
await t2.value
```

Will have a potential ordering output of:

```
Task 2 0
Task 2 1
Task 1 0
Task 1 1
Task 2 2
Task 1 2
Task 1 3
Task 1 4
Task 2 3
Task 2 4
```

In that example output Task 2 can get element 0 and 1 but must await until task 1 has caught up to the specified buffering. This limit means that no additional iteration (and no values are then dropped) is made until the buffer count is below the specified value.


## Effect on API resilience

This is an additive API and no existing systems are changed, however it will introduce a few new types that will need to be maintained as ABI interfaces. Since the intent of this is to provide a mechanism to store AsyncSequences to a shared context the type must be exposed as ABI (for type sizing).

## Alternatives considered

It has been considered that the buffering policy would be nested inside the `AsyncShareSequence` type. However since this seems to be something that will be useful for other types it makes sense to use an existing type from a top level type. However if it is determined that a general form of a  buffering policy would require additional behaviors this might be a debatable placement to move back to an interior type similar to AsyncStream.



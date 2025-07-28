# Share

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

It is not just likely but perhaps a certainty that other algorithms will end up needing the same concept of a buffering policy beyond just AsyncStream and the new sharing mechanism. A new type in AsyncAlgorithms will be introduced to handle this. [^BufferingPolicy]

```swift
/// A strategy that handles exhaustion of a buffer’s capacity.
public enum BufferingPolicy: Sendable {
  /// Continue to add to the buffer, without imposing a limit on the number
  /// of buffered elements.
  case unbounded
      
  /// When the buffer is full, discard the newly received element.
  ///
  /// This strategy enforces keeping at most the specified number of oldest
  /// values.
  case bufferingOldest(Int)
      
  /// When the buffer is full, discard the oldest element in the buffer.
  ///
  /// This strategy enforces keeping at most the specified number of newest
  /// values.
  case bufferingNewest(Int)
}
```

A new extension will be added to return a concrete type representing the share algorithm. This extension will take a buffering policy to identify how the buffer will be handled when iterations do not consume at the same rate.

A new AsyncSequence type will be introduced that is explicitly marked as `Sendable`. This annotation identifies to the developer that this sequence can be shared and stored. Because the type is intended to be stored it cannot be returned by the extension as a `some AsyncSequence<Element, Failure> & Sendable` since that cannot be assigned to a stored property. Additionally the type of `AsyncShareSequence`, since indented to be stored, will act as a quasi erasing-barrier to the type information of previous sequences in the chain of algorithms in that it will only hold the generic information of the `Element` and `Failure` as part of it's public interface and not the "Base" asynchronous sequence it was created from.

```swift
extension AsyncSequence where Element: Sendable {
  public func share(
    bufferingPolicy: BufferingPolicy = .unbounded
  ) -> AsyncShareSequence<Element, Failure>
}

public struct AsyncShareSequence<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? 
  }

  public func makeAsyncIterator() -> Iterator
}

@available(*, unavailable)
extension AsyncShareSequence.Iterator: Sendable { }
```

The buffer internally to the share algorithm will only extend back to the furthest element available but there will only be a singular buffer shared across all iterators. This ensures that with the application of the buffering policy the storage size is as minimal as possible while still allowing all iterations to avoid dropping values and keeping the memory usage in check.

## Runtime Behavior

The construction of the `AsyncShareSequence` will initially construct a shared iteration reference. This means that all instances of the structure of the `AsyncShareSequence` will reference to the same iteration.

Upon creation of the `Iterator` via `makeAsyncIterator` a new "side" will be constructed to identify the specific iterator interacting with the shared iteration. Then when next is invoked is where the first actual action takes place. 

The next method will first checkout from a critical region the underlying AsyncIterator from the base. If that is successful (i.e. no other iteration sides have already checked it out) then it will invoke the next method of that iterator (forwarding in the actor isolation). If an element is produced then it enqueues the element to the shared buffer, checks in the iterator, adjusts the index in the buffer, and finds all pending continuations all in a shared critical region by a mutex. Then those continuations will be resumed with the given element.

If no element is returned by the base iterator (signifying the terminal state);then the process is similar except it will instead mark the sequence as finished and resume with nil to any active continuations. Similarly with failures that will set the state as terminal but also store the error for further iteration points that need eventual termination.

Then all sides are "drained" such that continuations are placed into the shared state and resumed when an element is available for that position.

Practically this all means that a given iteration may be "behind" another and can eventually catch up (provided it is within the buffer limit).

```swift
let exampleSource = [0, 1, 2, 3, 4].async.share()

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

If the creation were altered to the following:

```swift
let exampleSource = [0, 1, 2, 3, 4].async.share(bufferingPolicy: .bufferingNewest(2))
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

## Usage 

It is expected that this operator will be unlike other

## Effect on API resilience

This is an additive API and no existing systems are changed, however it will introduce a few new types that will need to be maintained as ABI interfaces. Since the intent of this is to provide a mechanism to store AsyncSequences to a shared context the type must be exposed as ABI (for type sizing).

## Alternatives considered

[^BufferingPolicy] It has been considered that this particular policy would be nested inside the `AsyncShareSequence` type. However since this seems to be something that will be useful for other types it makes sense to expose it as a top level type. However if it is determined that a general form of a  buffering policy would require additional behaviors this might be a debatable placement to move back to an interior type similar to AsyncStream.



# Chunked & Timer
* Proposal: [SAA-0013](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0013-chunk.md)
* Author(s): [Kevin Perry](https://github.com/kperryua), [Philippe Hausler](https://github.com/phausler)
* Status: **Accepted**
* Implementation: [
[By group](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunkedByGroupSequence.swift),
[On projection](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunkedOnProjectionSequence.swift),
[Count and signal](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunksOfCountAndSignalSequence.swift)
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestChunk.swift)
]
[
[Timer](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncTimerSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestTimer.swift)
]
* Decision Notes:
* Bugs:

## Introduction

Grouping of values from an asynchronous sequence is often useful for tasks that involve writing those values efficiently or useful to handle specific structured data inputs. 

The groupings may be controlled by different ways but one most notable is to control them by regular intervals. Producing elements at regular intervals can be useful for composing with other algorithms. These can range from invoking code at specific times to using those regular intervals as a delimiter of events. There are other cases this exists in APIs however those do not currently interact with Swift concurrency. These existing APIs are ones like `Timer` or `DispatchTimer` but are bound to internal clocks that are not extensible.

## Proposed Solution

Chunking operations can be broken down into a few distinct categories: grouping according to a binary predicate used to determine whether consecutive elements belong to the same group, projecting an element's property to determine the element's chunk membership, by discrete count, by another signal asynchronous sequence which indicates when the chunk should be delimited, or by a combination of count and signal.

To satisfy the specific grouping by inteervals we propose to add a new type; `AsyncTimerSequence` which utilizes the new `Clock`, `Instant` and `Duration` types. This allows the interaction of the timer to custom implementations of types adopting `Clock`.

This asynchronous sequence will produce elements of the clock's `Instant` type after the interval has elapsed. That instant will be the `now` at the time that the sleep has resumed. For each invocation to `next()` the `AsyncTimerSequence.Iterator` will calculate the next deadline to resume and pass that and the tolerance to the clock. If at any point in time the task executing that iteration is cancelled the iteration will return `nil` from the call to `next()`.

## Detailed Design

### Grouping

Group chunks are determined by passing two consecutive elements to a closure which tests whether they are in the same group. When the `AsyncChunkedByGroupSequence` iterator receives the first element from the base sequence, it will immediately be added to a group. When it receives the second item, it tests whether the previous item and the current item belong to the same group. If they are not in the same group, then the iterator emits the first item's group and a new group is created containing the second item. Items declared to be in the same group accumulate until a new group is declared, or the iterator finds the end of the base sequence. When the base sequence terminates, the final group is emitted. If the base sequence throws an error, `AsyncChunkedByGroupSequence` will rethrow that error immediately and discard any current group.

```swift
extension AsyncSequence {
  public func chunked<Collected: RangeReplaceableCollection>(
    into: Collected.Type,
  	by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool 
  ) -> AsyncChunkedByGroupSequence<Self, Collected> 
  	where Collected.Element == Element

  public func chunked(
  	by belongInSameGroup: @escaping @Sendable (Element, Element) -> Bool
  ) -> AsyncChunkedByGroupSequence<Self, [Element]>
}
```

Consider an example where an asynchronous sequence emits the following values: `10, 20, 30, 10, 40, 40, 10, 20`. Given the chunked operation to be defined as follows:

```swift
let chunks = numbers.chunked { $0 <= $1 }
for await numberChunk in chunks {
  print(numberChunk)
}
```

That snippet will produce the following values:

```swift
[10, 20, 30]
[10, 40, 40]
[10, 20]
```

While `Array` is the default type for chunks, thanks to the overload that takes a `RangeReplaceableCollection` type, the same sample can be chunked into instances of `ContiguousArray`, or any other `RangeReplaceableCollection` instead.

```swift
let chunks = numbers.chunked(into: ContiguousArray.self) { $0 <= $1 }
for await numberChunk in chunks {
  print(numberChunk)
}
```

That variant is the funnel method for the main implementation, which passes `[Element].self` in as the parameter. 

### Projection

In some scenarios, chunks are determined not by comparing different elements, but by the element itself. This may be the case when the element has some sort of discriminator that can determine the chunk it belongs to. When two consecutive elements have different projections, the current chunk is emitted and a new chunk is created for the new element.

When the `AsyncChunkedOnProjectionSequence`'s iterator receives `nil` from the base sequence, it emits the final chunk. When the base sequence throws an error, the iterator discards the current chunk and rethrows that error.

Similarly to the `chunked(by:)` method this algorithm has an optional specification for the `RangeReplaceableCollection` which is used as the type of each chunk.

```swift
extension AsyncSequence {
  public func chunked<Subject : Equatable, Collected: RangeReplaceableCollection>(
    into: Collected.Type,
    on projection: @escaping @Sendable (Element) -> Subject
  ) -> AsyncChunkedOnProjectionSequence<Self, Subject, Collected>
  
  public func chunked<Subject : Equatable>(
  	on projection: @escaping @Sendable (Element) -> Subject
  ) -> AsyncChunkedOnProjectionSequence<Self, Subject, [Element]>
}
```

The following example shows how a sequence of names can be chunked together by their first characters.

```swift
let names = URL(fileURLWithPath: "/tmp/names.txt").lines
let groupedNames = names.chunked(on: \.first!)
for try await (firstLetter, names) in groupedNames {
  print(firstLetter)
  for name in names {
    print("  ", name)
  }
}
```

A special property of this kind of projection chunking is that when an asynchronous sequence's elements are known to be ordered, the output of the chunking asynchronous sequence is suitable for initializing dictionaries using the `AsyncSequence` initializer for `Dictionary`. This is because the projection can be easily designed to match the sorting characteristics and thereby guarantee that the output matches the pattern of an array of pairs of unique "keys" with the chunks as the "values".

In the example above, if the names are known to be ordered then you can take advantage of the uniqueness of each "first character" projection to initialize a `Dictionary` like so:

```swift
let names = URL(fileURLWithPath: "/tmp/names.txt").lines
let nameDirectory = try await Dictionary(uniqueKeysWithValues: names.chunked(on: \.first!))
```

### Count or Signal

Sometimes chunks are determined not by the elements themselves, but by external factors. This final category enables limiting chunks to a specific size and/or delimiting them by another asynchronous sequence which is referred to as a "signal". This particular chunking family is useful for scenarios where the elements are more efficiently processed as chunks than individual elements, regardless of their values.

This family is broken down into two sub-families of methods: ones that employ a signal plus an optional count (which return an `AsyncChunksOfCountOrSignalSequence`), and the ones that only deal with counts (which return an `AsyncChunksOfCountSequence`). Both sub-families have `Collected` as their element type, or `Array` if unspecified. These sub-families have rethrowing behaviors; if the base `AsyncSequence` can throw then the chunks sequence can also throw. Likewise if the base `AsyncSequence` cannot throw then the chunks sequence also cannot throw.

##### Count only

```swift
extension AsyncSequence {
  public func chunks<Collected: RangeReplaceableCollection>(
    ofCount count: Int, 
    into: Collected.Type
  ) -> AsyncChunksOfCountSequence<Self, Collected> 
    where Collected.Element == Element

  public func chunks(
    ofCount count: Int
  ) -> AsyncChunksOfCountSequence<Self, [Element]>
}
```

If a chunk size limit is specified via an `ofCount` parameter, the sequence will produce chunks of type `Collected` with at most the specified number of elements. When a chunk reaches the given size, the asynchronous sequence will emit it immediately.

For example, an asynchronous sequence of `UInt8` bytes can be chunked into at most 1024-byte `Data` instances like so:

```swift
let packets = bytes.chunks(ofCount: 1024, into: Data.self)
for try await packet in packets {
  write(packet)
}
```

##### Signal only

```swift
extension AsyncSequence {
  public func chunked<Signal, Collected: RangeReplaceableCollection>(
    by signal: Signal, 
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> 
    where Collected.Element == Element

  public func chunked<Signal>(
    by signal: Signal
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal>

  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(
    by timer: AsyncTimerSequence<C>, 
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> 
    where Collected.Element == Element

  public func chunked<C: Clock>(
    by timer: AsyncTimerSequence<C>
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>>
}
```

If a signal asynchronous sequence is specified, the chunking asynchronous sequence emits chunks whenever the signal emits. The signals element values are ignored. If the chunking asynchronous sequence hasn't accumulated any elements since its previous emission, then no value is emitted in response to the signal.

Since time is a frequent method of signaling desired delineations of chunks, there is a pre-specialized set of overloads that take `AsyncTimerSequence`. These allow shorthand initialization by using `AsyncTimerSequence`'s static member initializers.

As an example, an asynchronous sequence of log messages can be chunked into arrays of logs in four second segments like so:

```swift
let fourSecondsOfLogs = logs.chunked(by: .repeating(every: .seconds(4)))
for await chunk in fourSecondsOfLogs {
  send(chunk)
}
```

##### Count or Signal

```swift
extension AsyncSequence {
  public func chunks<Signal, Collected: RangeReplaceableCollection>(
    ofCount count: Int, 
    or signal: Signal, 
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> 
    where Collected.Element == Element

  public func chunks<Signal>(
    ofCount count: Int, 
    or signal: Signal
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal>

  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(
    by timer: AsyncTimerSequence<C>, 
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> 
    where Collected.Element == Element

  public func chunked<C: Clock>(
    by timer: AsyncTimerSequence<C>
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>>
}
```

If both count and signal are specified, the chunking asynchronous sequence emits chunks whenever *either* the chunk reaches the specified size *or* the signal asynchronous sequence emits. When a signal causes a chunk to be emitted, the accumulated element count is reset back to zero. When an `AsyncTimerSequence` is used as a signal, the timer is started from the moment `next()` is called for the first time on `AsyncChunksOfCountOrSignalSequence`'s iterator, and it emits on a regular cadence from that moment. Note that the scheduling of the timer's emission is unaffected by any chunks emitted based on count.

Like the example above, this code emits up to 1024-byte `Data` instances, but a chunk will also be emitted every second.

```swift
let packets = bytes.chunks(ofCount: 1024 or: .repeating(every: .seconds(1)), into: Data.self)
for try await packet in packets {
  write(packet)
}
```

In any configuration of any of the chunking families, when the base asynchronous sequence terminates, one of two things will happen: 1) a partial chunk will be emitted, or 2) no chunk will be emitted (i.e. the iterator received no elements since the emission of the previous chunk). No elements from the base asynchronous sequence are ever discarded, except in the case of a thrown error.

## Interfaces

### Grouping

```swift
public struct AsyncChunkedByGroupSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection>: AsyncSequence 
  where Collected.Element == Base.Element {
  public typealias Element = Collected
  
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Collected?
  }
  
  public func makeAsyncIterator() -> Iterator
}

extension AsyncChunkedByGroupSequence: Sendable 
  where Base: Sendable, Base.Element: Sendable { }
  
extension AsyncChunkedByGroupSequence.Iterator: Sendable 
  where Base.AsyncIterator: Sendable, Base.Element: Sendable { }
```

### Projection

```swift
public struct AsyncChunkedOnProjectionSequence<Base: AsyncSequence, Subject: Equatable, Collected: RangeReplaceableCollection>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = (Subject, Collected)

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> (Subject, Collected)?
  }

  public func makeAsyncIterator() -> Iterator
}

extension AsyncChunkedOnProjectionSequence: Sendable 
  where Base: Sendable, Base.Element: Sendable { }
extension AsyncChunkedOnProjectionSequence.Iterator: Sendable
  where Base.AsyncIterator: Sendable, Base.Element: Sendable, Subject: Sendable { }
```

### Count

```swift
public struct AsyncChunksOfCountSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection>: AsyncSequence 
  where Collected.Element == Base.Element {
  public typealias Element = Collected

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Collected?
  }

  public func makeAsyncIterator() -> Iterator
}

extension AsyncChunksOfCountSequence : Sendable where Base : Sendable, Base.Element : Sendable { }
extension AsyncChunksOfCountSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Base.Element : Sendable { }

```

### Count or Signal

```swift
public struct AsyncChunksOfCountOrSignalSequence<Base: AsyncSequence, Collected: RangeReplaceableCollection, Signal: AsyncSequence>: AsyncSequence, Sendable 
  where 
    Collected.Element == Base.Element, 
    Base: Sendable, Signal: Sendable, 
    Base.AsyncIterator: Sendable, Signal.AsyncIterator: Sendable, 
    Base.Element: Sendable, Signal.Element: Sendable {
  public typealias Element = Collected

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public mutating func next() async rethrows -> Collected?
  }
  
  public func makeAsyncIterator() -> Iterator
}
```

### Timer

```swift
public struct AsyncTimerSequence<C: Clock>: AsyncSequence {
  public typealias Element = C.Instant
  
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async -> C.Instant?
  }
  
  public init(
    interval: C.Instant.Duration, 
    tolerance: C.Instant.Duration? = nil, 
    clock: C
  )
  
  public func makeAsyncIterator() -> Iterator
}

extension AsyncTimerSequence where C == SuspendingClock {
  public static func repeating(every interval: Duration, tolerance: Duration? = nil) -> AsyncTimerSequence<SuspendingClock>
}

extension AsyncTimerSequence: Sendable { }
```

## Alternatives Considered

It was considered to make the chunked element to be an `AsyncSequence` instead of allowing collection into a `RangeReplaceableCollection` however it was determined that the throwing behavior of that would be complex to understand. If that hurdle could be overcome then that might be a future direction/consideration that would be worth exploring.

Variants of `chunked(by:)` (grouping) and `chunked(on:)` (projection) methods could be added that take delimiting `Signal` and `AsyncTimerSequence` inputs similar to `chunked(byCount:or:)`. However, it was decided that such functionality was likely to be underutilized and not worth the complication to the already broad surface area of `chunked` methods.

The naming of this family was considered to be `collect` which is used in APIs like `Combine`. This family of functions has distinct similarity to those APIs.

## Credits/Inspiration

This transformation function is a heavily inspired analog of the synchronous version [defined in the Swift Algorithms package](https://github.com/apple/swift-algorithms/blob/main/Guides/Chunked.md)

https://developer.apple.com/documentation/foundation/timer

https://developer.apple.com/documentation/foundation/timer/timerpublisher

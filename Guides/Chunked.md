# Chunked

* Author(s): [Kevin Perry](https://github.com/kperryua)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunkedByGroupSequence.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunkedOnProjectionSequence.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunkedOnProjectionSequence.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunksOfCountAndSignalSequence.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncChunksOfCountSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestChunk.swift)
]

## Introduction

Grouping of values from an asynchronous sequence is often useful for tasks that involve writing those values effeciently or useful to handle specific structured data inputs.

## Proposed Solution

Chunking operations can be broken down into a few distinct categories: grouping by  some sort of predicate determining if elements belong to the same group, projecting a property to determine the element's chunk, or by an optional discrete count in potential combination with a timed signal indicating when the chunk should be delimited.

### Grouping

Chunking by group can be determined by passing two elements to determine if they are in the same group. The first element awaited by iteration of a `AsyncChunkedByGroupSequence` will immediately be in a group, the second item will test that previous item along with the current one to determine if they belong to the same group. If they are not in the same group then the first item's group is emitted. Elsewise it will continue on until a new group is determined or the end of the sequence is reached. If an error is thrown during iteration of the base it will rethrow that error immediately and terminate any current grouping.

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

Consider an example where an async sequence emits the following values: `10, 20, 30, 10, 40, 40, 10, 20`. Given the chunked operation to be defined as follows:

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

That same sample could also be expressed as chunking into `ContiguousArray` types instead of `Array`.

```swift
let chunks = numbers.chunked(into: ContiguousArray.self) { $0 <= $1 }
for await numberChunk in chunks {
  print(numberChunk)
}
```

That variant is the funnel method for the default implementation that passes `Array<Element>.self` in as the parameter. 

### Projected Seperator

Other scenarios can determine the grouping behavior by the element itself. This is often times when the element contains some sort of descriminator about the grouping it belongs to. 

Similarly to the `chunked(by:)` API this algorithm has an optional specification for the `RangeReplacableCollection` that the chunks are comprised of. This means that other collection types other than just `Array` can be used to "packetize" the elements. 

When the base asynchronous sequence being iterated by `AsyncChunkedOnProjectionSequence` throws the iteration of the `AsyncChunkedOnProjectionSequence` rethrows that error. When the end of iteration occurs via returning nil from the iteration the iteration of the `AsyncChunkedOnProjectionSequence` then will return the final collected chunk.

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

Chunked asynchronous sequences on grouping can give iterative categorization or in the cases where it is known ordered elements suitable uniqueness for initializing dictionaries via the `AsyncSequence` initializer for `Dictionary`.

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

In the example above, if the names are known to be ordered then the uniqueness can be passed to `Dictionary.init(uniqueKeysWithValues:)`.

```swift
let names = URL(fileURLWithPath: "/tmp/names.txt").lines
let nameDirectory = try await Dictionary(uniqueKeysWithValues: names.chunked(on: \.first!))
```

### Count or Signal

The final category is to either delimit chunks of a specific count/size or by a signal. This particular transform family is useful for packetization where the packets being used are more effeciently handled as batches than individual elements.

This family is broken down into two sub-familes of methods. Ones that can transact upon a count or signal (which return a `AsyncChunksOfCountOrSignalSequence`), and the ones who only deal with counts (which return a `AsyncChunksOfCountSequence`). Both sub-familes have similar properties with the regards to the element they are producing; they both have the `Collected` as their element type. By default the produced element type is an array of the base asynchronous sequence's element. Iterating these sub-families have rethrowing behaviors; if the base `AsyncSequence` throws then the chunks sequence throws as well, likewise if the base `AsyncSequence` does not throw then the chunks sequence does not throw.

Any limitation upon the count of via the `ofCount` variants will produce `Collected` elements with at most the specified number of elements. At termination of these the final collected elements may be less than the specified count.

Since time is a critical method of signaling specific deliniations of chunks there is a pre-specialized variant of those methods for signals. These allow shorthand initialization via the static member initializers.

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

  public func chunked<Signal, Collected: RangeReplaceableCollection>(
    by signal: Signal, 
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, Signal> 
    where Collected.Element == Element

  public func chunked<Signal>(
    by signal: Signal
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], Signal>

  public func chunks<C: Clock, Collected: RangeReplaceableCollection>(
    ofCount count: Int, 
    or timer: AsyncTimerSequence<C>, 
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> 
    where Collected.Element == Element

  public func chunks<C: Clock>(
    ofCount count: Int, 
    or timer: AsyncTimerSequence<C>
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>>

  public func chunked<C: Clock, Collected: RangeReplaceableCollection>(
    by timer: AsyncTimerSequence<C>, 
    into: Collected.Type
  ) -> AsyncChunksOfCountOrSignalSequence<Self, Collected, AsyncTimerSequence<C>> 
    where Collected.Element == Element

  public func chunked<C: Clock>(
    by timer: AsyncTimerSequence<C>
  ) -> AsyncChunksOfCountOrSignalSequence<Self, [Element], AsyncTimerSequence<C>>
}

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

```swift
let packets = bytes.chunks(ofCount: 1024, into: Data.self)
for try await packet in packets {
  write(packet)
}
```

```swift
let fourSecondsOfLogs = logs.chunked(by: .repeating(every: .seconds(4)))
```

```swift
let packets = bytes.chunks(ofCount: 1024 or: .repeating(every: .seconds(1)), into: Data.self)
for try await packet in packets {
  write(packet)
}
```

## Detailed Design

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

### Projected Seperator

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

## Alternatives Considered

It was considered to make the chunked element to be an `AsyncSequence` instead of allowing collection into a `RangeReplacableCollection` however it was determined that the throwing behavior of that would be complex to understand. If that hurddle could be overcome then that might be a future direction/consideration that would be worth exploring.

The naming of this family was considered to be `collect` which is used in APIs like `Combine`. This family of functions has distinct similarity to those APIs.

## Credits/Inspiration

This transformation function is a heavily inspired analog of the synchronous version [defined in the Swift Algorithms package](https://github.com/apple/swift-algorithms/blob/main/Guides/Chunked.md)

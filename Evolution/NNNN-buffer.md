# Buffer

* Proposal: [SAA-NNNN](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/NNNN-buffer.md)
* Author(s): [Philippe Hausler](https://github.com/phausler)
* Status: **Implemented**
* Implementation: [
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncBufferSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestBuffer.swift)
]
* Decision Notes:
* Bugs:

## Introduction

Buffering is a common mechanism to smooth out demand to account for production that may be able to emit more quickly at some times than the requests come in for values. `AsyncStream` accomplishes this by offering control over the size of the buffer and the policy in which to deal with values after they exceed that size. That strategy works for many common cases, however it does not work for all scenarios and does not offer a mechanism to adapt other `AsyncSequence` types to have the buffering property. This proposal aims to offer a type that solves those more advanced cases but still expose it as a simple and approachable interface that is safe to use.

## Motivation

There are cases in which buffers can be more aptly implemented via coalescing, or can be more efficiently stored in specialized data structures for the element payloads. Granting advanced control over the way that buffers store values but still providing the safety of how to manipulate those buffers is key to making robust buffering tools for developers. 

In this proposal we will use an example of a dungeon game navigation as a stand in for these types of interactions; movement events will take the form of a number of moves north, south, east or west. The movements in this example start off as an `AsyncSequence` and subsequently iterated to derive additional state for the game, however if the iteration of those events is not as fast as the production then the values must be buffered to avoid dropping events. This contrived example is a stand-in for other more complicated systems and can be used to illustrate the mechanisms required for buffering.

The game example has a move enumeration that has an associated values for directions and combined directions and associated payloads to provide scalar amounts per those directions and a function to add an additional move to produce a sum of the movement vector. Moving east by 2 and then moving west by 1 sums to a movement of east by 1 etc.

```swift
enum Move {
	case north(Int)
	case northWest(Int, Int)
	case west(Int)
	case southWest(Int, Int)
	case south(Int)
	case southEast(Int, Int)
	case east(Int)
	case northEast(Int, Int)
	
	func add(_ other: Move) -> Move { ... }
}
```

This means that when we push additional values into the buffer we only need to store one value for the total movement and a normal array or deque storage would not be the most efficient method to store things. This of course becomes more pertanent when the values being stored are considerably more complex than just a movement enumeration. 

However the other part to the complexity is the management of when to push values into the buffer and when to pop values out as well as maintaining concurrency safe state of those values. This is precisely where the buffer algorithm comes in to offer a simple interface for doing so by leveraging the language features for concurrency to ensure safe access.

## Proposed Solution

The buffer algorithm comes in a few distinct parts; the algorithm for buffering values, a definition of how to manipulate those values safely, and a common use case scenario based on normal collection based storage.

At the heart of the buffer algorithm is a definition of how to asynchronously store values and how to remove values from that storage. It is not required for those values to be the same type; it is reasonable in more advanced cases for the elements being pushed into the buffer to be differing from the elements being popped off. In the example of the moves for the dungeon game it could be reasonable to push individual `Move` elements into the buffer but then pop arrays of `Move` elements off. Furthermore, in some cases it is meaningful to describe failures of the pop function to indicate that some condition has created a failure mode. This means that the buffer type needs to have flexibility for both its output independent to its input as well as being able to be a source of rethrowing failures. Since this buffer is intended for asynchronous operation it means that all values must be manipulated in their own island of concurrency; pushing and popping values must share the same access isolation together. Putting this all together means that the `AsyncBuffer` definition then is a protocol requiring being an actor with associated types for output and input and requirements for pushing and popping such that the pop method may contribute to the throwing nature of the resulting `AsyncSequence`.

```swift
/// An asynchronous buffer storage actor protocol used for buffering
/// elements to an `AsyncBufferSequence`.
@rethrows
public protocol AsyncBuffer: Actor {
  associatedtype Input: Sendable
  associatedtype Output: Sendable

  /// Push an element to enqueue to the buffer
  func push(_ element: Input) async
  
  /// Pop an element from the buffer.
  ///
  /// Implementors of `pop()` may throw. In cases where types
  /// throw from this function, that throwing behavior contributes to
  /// the rethrowing characteristics of `AsyncBufferSequence`.
  func pop() async throws -> Output?
}
```

One of the most common buffering strategies is to buffer into a mutable collection and limit by a policy of how to handle elements, this limit can be either unbounded, buffering oldest or buffering newest values. This takes a inspiration directly from `AsyncStream` and grants developers a mechanism for replicating the buffering strategies for `AsyncStream` on any `AsyncSequence`.

```swift
public actor AsyncLimitBuffer<Element: Sendable>: AsyncBuffer {
  /// A policy for buffering elements to an `AsyncLimitBuffer`
  public enum Policy: Sendable {
    /// A policy for no bounding limit of pushed elements.
    case unbounded
    /// A policy for limiting to a specific number of oldest values.
    case bufferingOldest(Int)
    /// A policy for limiting to a specific number of newest values.
    case bufferingNewest(Int)
  }
  
  public func push(_ element: Element) async 
  public func pop() async -> Element?
}
```

Putting those together with an `AsyncSequence` then grants a more general form for specifying how to create a given buffer and then a more specific version that specifies a limit policy. 

```swift
extension AsyncSequence where Element: Sendable, Self: Sendable {
  /// Creates an asynchronous sequence that buffers elements using a buffer created from a supplied closure.
  ///
  /// Use the `buffer(_:)` method to account for `AsyncSequence` types that may produce elements faster
  /// than they are iterated. The `createBuffer` closure returns a backing buffer for storing elements and dealing with
  /// behavioral characteristics of the `buffer(_:)` algorithm.
  ///
  /// - Parameter createBuffer: A closure that constructs a new `AsyncBuffer` actor to store buffered values.
  /// - Returns: An asynchronous sequence that buffers elements using the specified `AsyncBuffer`.
  public func buffer<Buffer: AsyncBuffer>(_ createBuffer: @Sendable @escaping () -> Buffer) -> AsyncBufferSequence<Self, Buffer> where Buffer.Input == Element
  
  /// Creates an asynchronous sequence that buffers elements using a specific policy to limit the number of
  /// elements that are buffered.
  ///
  /// - Parameter policy: A limiting policy behavior on the buffering behavior of the `AsyncBufferSequence`
  /// - Returns: An asynchronous sequence that buffers elements up to a given limit.
  public func buffer(policy limit: AsyncLimitBuffer<Element>.Policy) -> AsyncBufferSequence<Self, AsyncLimitBuffer<Element>>
}

public struct AsyncBufferSequence<Base: AsyncSequence & Sendable, Buffer: AsyncBuffer>: Sendable where Base.Element == Buffer.Input { }

extension AsyncBufferSequence: AsyncSequence {
  public typealias Element = Buffer.Output
  
  /// The iterator for a `AsyncBufferSequence` instance.
  public struct Iterator: AsyncIteratorProtocol {
  	public mutating func next() async rethrows -> Element?
  }
  
  public func makeAsyncIterator() -> Iterator
}
```

## Detailed Design

The `AsyncBuffer` type was specifically chosen to be an actor; that way no matter the access that may occur the stored elements of the buffer is isolated. The buffer can define exactly how the elements behave when pushed as well as how they behave when popped. Returning nil from the pop method means that the buffer does not have any available elements and must be called after additional elements are pushed into it. Any time at which the base of the `AsyncBufferSequence` returns nil, this means that if the buffer ever returns nil from the pop method that indicates the sequence is complete and returns nil downstream. If pop ever throws that indicates the sequence is in a terminal state and that failure is then rethrown in the iteration. 

```swift
actor MoveBuffer: AsyncBuffer {
  var currentMove: Move?
  func push(_ move: Move) async {
    if let currentMove {
      currentMove = currentMove.add(move)
    } else {
      currentMove = move
    }
  }
  
  func pop() async -> Move? {
    defer { currentMove = nil }
    return currentMove
  }
}
```

Since `AsyncBuffer` types are actors, it is also conceivable that a buffer could be shared among many accessors. This particular pattern (albeit most likely an uncommon design) is legitimate to return a shared buffer from the construction closure; thusly sharing the buffer among all potential instances of sequences using it. 

Unlike the general purpose `AsyncBuffer` the `AsyncLimitBuffer` cannot be directly constructed - it is instead constructed internally given the specified policy. The type being public means that the generic for the `AsyncBufferSequence` is exposed and part of the signature; indicating both the type of buffering that is occurring but also allowing for performance optimizations to occur.

This all means that given the following code:

```swift
let bufferedMoves = game.moves.buffer { MoveBuffer() }
for await move in bufferedMoves {
  await processMove(move)
}
```

This will allow for custom buffering of the elements with efficient storage and a simple interface to allow for that customization. This approach gives us the flexibility of custom buffers but the ease of use of a simple call site and retains the safety of how Swift's language level concurrency favors. 

## Notes on Sendable

Since all buffering means that the base asynchronous sequence must be iterated independently of the consumption (to resolve the production versus consumption issue) both the base `AsyncSequence` and the element of which need to be able to be sent across task boundaries (the iterator does not need this requirement). The `AsyncBuffer` itself needs to also be `Sendable` since it will be utilized in two distinct tasks; the production side of things iterating the base, and the consumption side of things iterating the `AsyncBufferSequence` itself. Thankfully in the case of the `AsyncBuffer` actor types are inherently `Sendable`. 

## Alternatives Considered

The buffer type was considered to be expected to be a sendable structure, however this meant that mutations of that structure would then be in an isolation that was internal to the buffer itself. We decided that this is perhaps an incorrect design pattern in that it exposes the user to potentials of deadlocks or at best isolation that escaped private implementations.

The buffer protocol definition could potentially throw on the push as well as the pop, and this is still an open point of consideration.

`AsyncLimitBuffer` could be externally constructible (e.g. the `init(policy:)` could be exposed as `public`). This is an open point of consideration, however the utility of which is dubious. With sufficient motivation, that could be exposed at a later point.

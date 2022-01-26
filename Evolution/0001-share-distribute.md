# Share and Distribute

* Proposal: [0001](0001-share-distribute.md)
* Author(s): [Philippe Hausler](https://github.com/phausler)
* Review Manager: 
* Status: **Draft**

## Revision History
* **v1** Initial draft

## Introduction

AsyncSequence was designed particularly for singular sequences of values; a pipeline from the production of values to the consumption of them. However not all topologies of applications have this data flow structure. It is quite common to have many areas in an application need to share the same resource, but that sharing can need differing semantics.

For this pitch I will use an analogy of a deck of cards to illustrate some of these concepts and hopefully illuminate the subtile differences for the requirements of a solution.

## Motivation

Imagine an async sequence representing a deck of shuffled cards. That async sequence is comprised of unique values. Each card has a distinct value from each other card. When dealing these digital cards there are two ways to consider dealing them (iterating), either you individually per player deal out the cards distinct to that player _or_ you distribute the values to all interested parties about that card (in real-life semantics; placing the card face up). These two actions are the same root; dealing from the deck. However there is one semantical difference, either the cards are handed out to the parties ready to take them without the need to know how many parties are interested, or the cards are placed in a shared area and you await dealing the next card until all interested parties have determined they have seen that card.

The analogy of cards can be reflected back into swift concurrency. The action of handing out cards to an unknown number of players is the actor model. In that, the action of dealing is the isolation of the actor upon iteration. This means that the consumption of that iterator is isolate and then able to be sent to whatever task provided the element itself that is being distributed is sendable. The other method of showing cards face up is a sharing option where a singular resource is shared among many interested parties. This latter approach models the concept of sharing a sequence to avoid the replication of work similar to how share works today in Combine. The one key difference is that share in combine attempts to merge these two concepts into one singular form and let demand drive any potential issue of dropped values. Even though awaiting on async functions is a modeling of demand, it means that any application is always a demand of 1, and in turn that means that there is a potential of dropping a value as soon as something is not awaiting the function. By splitting the concept into its two distinct forms, we can either distribute consumption of the iterator or we can await sharing the value to all interested parties and apply back pressure to the system via awaiting the full consumption of the value (every player indicating they have seen the face up card).

## Detailed Design

This distribute and share concept can be expressed in terms of asynchronous sequences with some relatively simple interfaces. We propose to introduce two extensions on `AsyncSequence` that have functions to construct these concepts. 

The `distribute` function will return an `AsyncSequence` that is an `actor` (and also be an actor for the iterator) where the `Element` is `Sendable`. And the `share` function will take a value indicating how many ways the sequence is shared and returns an `AsyncSequence` that provides the elements such that they can be indicated of their consumption to provide back pressure to the iteration.

```swift
extension AsyncSequence where Element: Sendable {
  public func distribute() -> AsyncDistributedSequence<Self>
}

public actor AsyncDistributedSequence<Base: AsyncSequence>: AsyncSequence, AsyncIteratorProtocol {
  public nonisolated func makeAsyncIterator() -> Self

  public func next() async rethrows -> Base.Element?
}

extension AsyncSequence {
  public func share(_ ways: Int) -> [AsyncSharedSequence<Self>]
}

public struct AsyncSharedSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Base.Element?
  }

  public func makeAsyncIterator() -> Iterator
}

extension AsyncSharedSequence: Sendable where Base.Element: Sendable { }
extension AsyncSharedSequence.Iterator: Sendable where Base.Element: Sendable { }
```

This has immediate usefulness to existing API such as `AsyncStream` since that type does not provide a mechanism to allow for the affordance of iteration from multiple tasks. These operators immediately define that semantic and provide safe and descriptive interfaces to indicate the intent of how the values will be used from those tasks; either the iteration is a consuming semantic, or the values are shared among a known number of interested parties.

### Distribute

The implementation of this operator actor is relatively trivial; effectively the actor creates an iterator upon initialization and each consumption is isolated on that actor. This can easily be considered to the antithesis of the `merge` combinator. 

```swift
let input = Set([1, 2, 3])
let distributed = input.async.distributed()
let combined = merge(distributed, distributed)
let output = await Set(combined)
assert(input == output)
```

Not every combinator needs to have an antithesis operator, but in this case it allows for useful consumption of the iteration to be used for algorithms such as round-robin processing. 

### Share

The `share` operator is a bit more complex than its counterpart. In general application development this is likely the more common of the two; where multiple interested parties can await values from the same source. This operator can be viewed as the antithesis of the `zip` combinator. 

```swift
let input = [(1, "a"), (2, "b"), (3, "c")]  
let shared = input.async.share(2)
let combined = zip(shared[0], shared[1])
let output = await Set(combined)
assert(input == output) // provided if arrays of tuples were actually equatable
```

Each iteration of the base sequence will await the consumption of all active sides. This has the distinct advantage in comparison to an unbounded share that when no more consumers exist in an active state the resources for the iteration can be disposed.

## Existing Application Code

This proposal is purely additive and has no direct impact to existing application code.

## Impact on ABI

This proposal has no impact upon ABI.

## Alternatives Considered

It has been considered to only offer one singular share operation, however that can result in dropped values and not offer a way to understand individual side cancellations.


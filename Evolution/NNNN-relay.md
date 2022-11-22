# Relay

* Proposal: [SAA-NNNN](NNNN-relay.md)
* Authors: [Tristan Celder](https://github.com/tcldr)
* Review Manager: TBD
* Status: **Implemented. Awaiting Feedback.**


 * Implementation: [[Source](https://github.com/tcldr/swift-async-algorithms/blob/pr/relay/Sources/AsyncAlgorithms/AsyncRelay.swift) |
 [Tests](https://github.com/tcldr/swift-async-algorithms/blob/pr/relay/Tests/AsyncAlgorithmsTests/TestRelay.swift)]

## Introduction

Swift's built in language features for asynchronous sequences provide a lightweight, ergonomic syntax for consuming elements from an asynchronous source, but creating those asynchronous sequences can sometimes feel a little more involved. `AsyncStream` works very well in its role of adapting traditional event sources into the world of structured concurrency, but there isn't an equivalent convenience for creating a natively asynchronous source.

For example, if we wanted to output the Fibonacci seqeunce asynchronously as an `AsyncSequence`, we'd need to create a type similar to the following:

```swift

// This could of course be implemented as a non-async `Sequence`, but serves
// well for illustrative purposes 
struct AsyncFibonacciSequence: AsyncSequence: Sendable {
  
  typealias Element = Int
  
  struct Iterator: AsyncIteratorProtocol {
    
    var seed = (0, 1)
    
    mutating func next() async -> Element? {
      if Task.isCancelled { return nil }
      defer { seed = (seed.1, seed.0 + seed.1) }
      return seed.0
    }
  }
  
  func makeAsyncIterator() -> Iterator {
    Iterator()
  }
}

let fibonacci = AsyncFibonacciSequence()

```

For simple routines, writing this amount of code creates unnecessary friction for programmers.

In addition, it's difficult to share the sequence amongst tasks. While the sequence _does_ conform to `Sendable`, its iterator does not. This means that each time the sequence is iterated, it starts from the beginning. To circumvent this, a programmer may attempt to share an asynchronous sequence's iterator instead. But this would result in a compiler warning (and soon to be error) about attempting to send non-`Sendable` items across actor boundaries.

## Proposed solution

Asynchronous relays work in a similar way to what are sometimes called 'generators' in other languages. They expose a convenient shorthand that makes creating a producing asynchronous sequence, nearly as frictionless as consuming an asynchronous sequence.

Here's how the Fibonacci asynchronous sequence above could be converted to an asynchronous relay with equivalent functionality:

```swift  
let fibonacci = AsyncRelaySequence { yield in
  var seed = (0, 1)
  while !Task.isCancelled {
    await yield(seed.0)
    seed = (seed.1, seed.0 + seed.1)
  }
}
```

But often, it's desirable to share a producing iterator across `Task`s. `AsyncRelay` faciliates this directly without a requirement to call `AsyncRelaySequence`s `makeAsyncIterator()` method:

```swift

// Now just `AsyncRelay` instead of `AsyncRelaySequence`
let fibonacci = AsyncRelay { yield in 
  var seed = (0, 1)
  while !Task.isCancelled {
    await yield(seed.0)
    seed = (seed.1, seed.0 + seed.1)
  }
}

Task {
  let fib1 = await fibonacci.next()
  ...
}
Task {
  let fib2 = await fibonacci.next()
  ...
}
Task {
  let fib3 = await fibonacci.next()
  ...
}

```

`AsyncRelay` also has sibling throwing varieties, `AsyncThrowingRelay` and `AsyncThrowingRelaySequence`, which leverage Swift's built in control flow syntax to shutdown a relay when an `Error` is thrown. 

```swift
let imageRequest1 = ...
let imageRequest2 = ...
let imageRequest3 = ...
let relay = AsyncThrowingRelay { yield in 
  await yield(try await imageRequest1.fetch()) // Good.
  await yield(try await imageRequest2.fetch()) // Throws! Relay will exit here and cancel.
  await yield(try await imageRequest3.fetch()) // Doesn't get called.
}

// Somewhere else is the code... 

do {
  let image1 = try await relay.next() // Great.
  let image2 = try await relay.next() // Uh-oh, Throws! 
  let image3 = try await relay.next() // Doesn't get called.
}
...

```

## Detailed design

```swift
// An asynchronous sequence generated from a closure that limits its rate of
// element production to the rate of element consumption
//
// ``AsyncRelaySequence`` conforms to ``AsyncSequence``, providing a convenient
// way to create an asynchronous sequence without manually conforming a type
// ``AsyncSequence``.
//
// You initialize an ``AsyncRelaySequence`` with a closure that receives an
// ``AsyncRelay.Continuation``. Produce elements in this closure, then provide
// them to the sequence by calling the suspending continuation. Execution will
// resume as soon as the produced value is consumed. You call the continuation
// instance directly because it defines a `callAsFunction()` method that Swift
// calls when you call the instance. When there are no further elements to
// produce, simply allow the function to exit. This causes the sequence
// iterator to produce a nil, which terminates the sequence.
//
// Both ``AsyncRelaySequence`` and its iterator ``AsyncRelay`` conform to
// ``Sendable``, which permits them being called from from concurrent contexts.
public struct AsyncRelaySequence<Element: Sendable> : Sendable, AsyncSequence {
  public typealias AsyncIterator = AsyncRelay<Element>
  public init(_ producer: @escaping AsyncIterator.Producer)
  public func makeAsyncIterator() -> AsyncRelay<Element>
}

// An asynchronous sequence iterator generated from a closure that limits its
// rate of element production to the rate of element consumption
//
// For usage information see ``AsyncRelaySequence``.
//
// ``AsyncRelay`` conforms to ``Sendable``, which permits calling it from
// concurrent contexts.
public struct AsyncRelay<Element: Sendable> : Sendable, AsyncIteratorProtocol {
  
  public typealias Producer = @Sendable (Continuation) async -> Void
  
  public struct Continuation {    
    public func callAsFunction(_ element: Element) async
  }  
  public func next() async -> Element?
}

// A throwing asynchronous sequence generated from a closure that limits its
// rate of element production to the rate of element consumption
//
// ``AsyncThrowingRelaySequence`` conforms to ``AsyncSequence``, providing a
// convenient way to create a throwing asynchronous sequence without manually
// conforming a type ``AsyncSequence``.
//
// You initialize an ``AsyncThrowingRelaySequence`` with a closure that
// receives an ``AsyncThrowingRelay.Continuation``. Produce elements in this
// closure, then provide them to the sequence by calling the suspending
// continuation. Execution will resume as soon as the value produced is
// consumed. You call the continuation instance directly because it defines a
// `callAsFunction()` method that Swift calls when you call the instance. When
// there are no further elements to produce, simply allow the function to exit.
// This causes the sequence to produce a nil, which terminates the sequence.
// You may also choose to throw from within the closure which terminates the
// sequence with an ``Error``.
//
// Both ``AsyncThrowingRelaySequence`` and its iterator ``AsyncThrowingRelay``
// conform to ``Sendable``, which permits them being called from from
// concurrent contexts.
public struct AsyncThrowingRelaySequence<Element: Sendable> : Sendable, AsyncSequence {
  
  public typealias AsyncIterator = AsyncThrowingRelay<Element>  
  public init(_ producer: @escaping AsyncIterator.Producer)  
  public func makeAsyncIterator() -> AsyncThrowingRelay<Element>
}

// A throwing asynchronous sequence iterator generated from a closure that
// limits its rate of element production to the rate of element consumption
//
// For usage information see ``AsyncThrowingRelaySequence``.
//
// ``AsyncThrowingRelay`` conforms to ``Sendable``, which permits calling it
// from concurrent contexts.
public struct AsyncThrowingRelay<Element: Sendable> : Sendable, AsyncIteratorProtocol {
  public typealias Producer = @Sendable (Continuation) async throws -> Void
  public struct Continuation {
    public func callAsFunction(_ element: Element) async
  }
  public init(_ producer: @escaping Producer)
  public func next() async throws -> Element?
}
```

## Acknowledgmenets

Asynchronous relays are heavily inspired by generators and sequence builders available in other languages.

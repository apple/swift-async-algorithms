# Combine Latest

[[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncCombineLatest2Sequence.swift), [Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncCombineLatest3Sequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestCombineLatest.swift)]

Combines the latest values produced from two or more asynchronous sequences into an asynchronous sequence of tuples.

```swift
let appleFeed = URL("http://www.example.com/ticker?symbol=AAPL").lines
let nasdaqFeed = URL("http://www.example.com/ticker?symbol=^IXIC").lines

for try await (apple, nasdaq) = combineLatest(appleFeed, nasdaqFeed) {
  print("APPL: \(apple) NASDAQ: \(nasdaq)")
}
```

## Detailed Design

This function family and the associated family of return types are prime candidates for variadic generics. Until that proposal is accepted these will be implemented in terms of two and three base sequence cases.

```swift
public func combineLatest<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncCombineLatest2Sequence<Base1, Base2>

public func combineLatest<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(_ base1: Base1, _ base2: Base2, _ base3: Base3) -> AsyncCombineLatest3Sequence<Base1, Base2, Base3>

public struct AsyncCombineLatest2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: Sendable
  where
    Base1: Sendable, Base2: Sendable,
    Base1.Element: Sendable, Base2.Element: Sendable,
    Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable {
  public typealias Element = (Base1.Element, Base2.Element)

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

public struct AsyncCombineLatest3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
  where
    Base1: Sendable, Base2: Sendable, Base3: Sendable
    Base1.Element: Sendable, Base2.Element: Sendable, Base3.Element: Sendable
    Base1.AsyncIterator: Sendable, Base2.AsyncIterator: Sendable, Base3.AsyncIterator: Sendable {
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)

  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async rethrows -> Element?
  }

  public func makeAsyncIterator() -> Iterator
}

```

The `combineLatest(_:...)` function takes two or more asynchronous sequences as arguments with the resulting `AsyncCombineLatestSequence` which is an asynchronous sequence.

Since the bases comprising the `AsyncCombineLatestSequence` must be iterated concurrently to produce the latest value it means that those sequences must be able to be sent to child tasks. This means that a prerequisite of the bases must be that the base asynchronous sequences, their iterators, and the elemnts they produce must be `Sendable`. 

If any of the bases terminate before the first element is produced then the `AsyncCombineLatestSequence` iteration can never be satisfied so if a base's iterator returns nil at the first iteration then the `AsyncCombineLatestSequence` iterator immediately returns nil to signify a terminal state. In this particular case any outstanding iteration of other bases will be cancelled. After the first element is produced this behavior is different since the latest values can still be satisfied by at least one base. This means that beyond the construction of the first tuple comprised of the returned elements of the base the terminal state of the `AsyncCombineLatestSequence` iteration will only be reached when all of the base iterations reach a terminal state.

The throwing behavior of `AsyncCombineLatestSequence` is that if any of the bases throw then the composed asynchronous sequence then throws on its iteration. If at any point (within the first or afterwards) an error is thrown by any base, the other iterations are cancelled and the thrown error is immediately thrown to the consuming iteration.

### Naming

Since the inherent behavior of `combineLatest(_:...)` combines the latest values from multiple streams into a tuple the naming is intended to be quite literal. There are precident terms of art in other frameworks and libraries (listed in the comparison section). Other naming takes the form of "withLatestFrom". This was disregarded since the "with" prefix is often most associated with the passing of a closure and some sort of contextual concept; `withUnsafePointer` or `withUnsafeContinuation` are prime examples.

### Comparison with other libraries

Combine latest often appears in libraries developed for processing events over time since the event ordering of a concept of "latest" only occurs when asynchrony is involved.

**ReactiveX** ReactiveX has an [API definition of CombineLatest](https://reactivex.io/documentation/operators/combinelatest.html) as a top level function for combinining Observables.

**Combine** Combine has an [API definition of combineLatest](https://developer.apple.com/documentation/combine/publisher/combinelatest(_:)/) has an operator style method for combining Publishers.

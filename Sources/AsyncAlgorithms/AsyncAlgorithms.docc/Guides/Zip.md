# Zip

Combines the latest values produced from two or more asynchronous sequences into an asynchronous sequence of tuples.

[[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Zip/AsyncZip2Sequence.swift), [Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Zip/AsyncZip3Sequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestZip.swift)]

```swift
let appleFeed = URL(string: "http://www.example.com/ticker?symbol=AAPL")!.lines
let nasdaqFeed = URL(string: "http://www.example.com/ticker?symbol=^IXIC")!.lines

for try await (apple, nasdaq) in zip(appleFeed, nasdaqFeed) {
  print("APPL: \(apple) NASDAQ: \(nasdaq)")
}
```

Given some sample inputs the following zipped events can be expected.

| Timestamp   | appleFeed | nasdaqFeed | combined output               |                 
| ----------- | --------- | ---------- | ----------------------------- |
| 11:40 AM    | 173.91    |            |                               |
| 12:25 AM    |           | 14236.78   | AAPL: 173.91 NASDAQ: 14236.78 |
| 12:40 AM    |           | 14218.34   |                               |
|  1:15 PM    | 173.00    |            | AAPL: 173.00 NASDAQ: 14218.34 |

## Detailed Design

This function family and the associated family of return types are prime candidates for variadic generics. Until that proposal is accepted, these will be implemented in terms of two- and three-base sequence cases.

```swift
public func zip<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncZip2Sequence<Base1, Base2>

public func zip<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(_ base1: Base1, _ base2: Base2, _ base3: Base3) -> AsyncZip3Sequence<Base1, Base2, Base3>

public struct AsyncZip2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: Sendable
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

public struct AsyncZip3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
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

The `zip(_:...)` function takes two or more asynchronous sequences as arguments with the resulting `AsyncZipSequence` which is an asynchronous sequence.

Each iteration of an `AsyncZipSequence` will await for all base iterators to produce a value. This iteration will be done concurrently to produce a singular tuple result. If any of the base iterations terminates by returning `nil` from its iteration, the `AsyncZipSequence` iteration is immediately considered unsatisfiable and returns `nil` and all iterations of other bases will be cancelled. If any iteration of the bases throws an error, then the other iterations concurrently running are cancelled and the produced error is rethrown, terminating the iteration.

`AsyncZipSequence` requires that the iterations are done concurrently. This means that the base sequences, their elements, and iterators must all be `Sendable`. That makes `AsyncZipSequence` inherently `Sendable`.

The source of throwing of `AsyncZipSequence` is determined by its bases. That means that if any base can throw an error then the iteration of the `AsyncZipSequence` can throw. If no bases can throw, then the `AsyncZipSequence` does not throw.

### Naming

The `zip(_:...)` function takes its name from the Swift standard library function of the same name. The `AsyncZipSequence` family of types take their name from the same family from the standard library for the type returned by `zip(_:_:)`. The one difference is that this asynchronous version allows for the affordance of recognizing the eventual variadic generic need of expanding a zip of more than just two sources.

It is common in some libraries to have a `ZipMap` or some other combination of `zip` and `map`. This is a common usage pattern, but leaving a singular type for composition feels considerably more approachable.

### Comparison with other libraries

**Swift** The swift standard library has an [API definition of zip](https://developer.apple.com/documentation/swift/1541125-zip) as a top level function for combining two sequences.

**ReactiveX** ReactiveX has an [API definition of Zip](https://reactivex.io/documentation/operators/zip.html) as a top level function for combining Observables.

**Combine** Combine has an [API definition of zip](https://developer.apple.com/documentation/combine/publisher/zip(_:)/) as an operator style method for combining Publishers.

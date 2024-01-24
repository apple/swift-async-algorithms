# swift-async-algorithms

**Swift Async Algorithms** is an open-source package of asynchronous sequence and advanced algorithms that involve concurrency, along with their related types.

This package has three main goals:

- First-class integration with `async/await`
- Provide a home for time-based algorithms
- Be cross-platform and open source

## Motivation

 AsyncAlgorithms is a package for algorithms that work with *values over time*. That includes those primarily about *time*, like `debounce` and `throttle`, but also algorithms about *order* like `combineLatest` and `merge`. Operations that work with multiple inputs (like `zip` does on `Sequence`) can be surprisingly complex to implement, with subtle behaviors and many edge cases to consider. A shared package can get these details correct, with extensive testing and documentation, for the benefit of all Swift apps.

 The foundation for AsyncAlgorithms was included in Swift 5.5 from [AsyncSequence](https://github.com/apple/swift-evolution/blob/main/proposals/0298-asyncsequence.md). Swift 5.5 also brings the ability to use a natural `for/in` loop with `await` to process the values in an `AsyncSequence` and `Sequence`-equivalent API like `map` and `filter`. Structured concurrency allows us to write code where intermediate state is simply a local variable, `try` can be used directly on functions that `throw`, and generally treat the logic for asynchronous code similar to that of synchronous code.

This package is the home for these APIs. Development and API design take place on [GitHub](https://github.com/apple/swift-async-algorithms) and the [Swift Forums](https://forums.swift.org/c/related-projects/swift-async-algorithms).

## Contents

#### Combining asynchronous sequences

- [`chain(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Chain.md): Concatenates two or more asynchronous sequences with the same element type. 
- [`combineLatest(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/CombineLatest.md): Combines two or more asynchronous sequences into an asynchronous sequence producing a tuple of elements from those base asynchronous sequences that updates when any of the base sequences produce a value.
- [`merge(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Merge.md): Merges two or more asynchronous sequence into a single asynchronous sequence producing the elements of all of the underlying asynchronous sequences.
- [`zip(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Zip.md): Creates an asynchronous sequence of pairs built out of underlying asynchronous sequences.
- [`joined(separator:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Joined.md): Concatenated elements of an asynchronous sequence of asynchronous sequences, inserting the given separator between each element.

#### Creating asynchronous sequences

- [`async`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Lazy.md): Create an asynchronous sequence composed from a synchronous sequence.
- [`AsyncChannel`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Channel.md): An asynchronous sequence with back pressure sending semantics.
- [`AsyncThrowingChannel`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Channel.md): An asynchronous sequence with back pressure sending semantics that can emit failures.

#### Performance optimized asynchronous iterators

- [`AsyncBufferedByteIterator`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/BufferedBytes.md): A highly efficient iterator useful for iterating byte sequences derived from asynchronous read functions.

#### Other useful asynchronous sequences
- [`adjacentPairs()`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/AdjacentPairs.md): Collects tuples of adjacent elements.
- [`chunks(...)` and `chunked(...)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Chunked.md): Collect values into chunks.
- [`compacted()`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Compacted.md): Remove nil values from an asynchronous sequence.
- [`removeDuplicates()`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/RemoveDuplicates.md): Remove sequentially adjacent duplicate values.
- [`interspersed(with:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Intersperse.md): Place a value between every two elements of an asynchronous sequence.

#### Asynchronous Sequences that transact in time

- [`debounce(for:tolerance:clock:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Debounce.md): Emit values after a quiescence period has been reached.
- [`throttle(for:clock:reducing:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Throttle.md): Ensure a minimum interval has elapsed between events.
- [`AsyncTimerSequence`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Timer.md): Emit the value of now at a given interval repeatedly.

#### Obtaining all values from an asynchronous sequence

- [`RangeReplaceableCollection.init(_:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Collections.md): Creates a new instance of a collection containing the elements of an asynchronous sequence.
- [`Dictionary.init(uniqueKeysWithValues:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Collections.md): Creates a new dictionary from the key-value pairs in the given asynchronous sequence.
- [`Dictionary.init(_:uniquingKeysWith:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Collections.md): Creates a new dictionary from the key-value pairs in the given asynchronous sequence, using a combining closure to determine the value for any duplicate keys.
- [`Dictionary.init(grouping:by:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Collections.md): Creates a new dictionary whose keys are the groupings returned by the given closure and whose values are arrays of the elements that returned each key.
- [`SetAlgebra.init(_:)`](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Collections.md): Creates a new set from an asynchronous sequence of items.

#### Effects

Each algorithm has specific behavioral effects. For throwing effects these can either be if the sequence throws, does not throw, or rethrows errors. Sendability effects in some asynchronous sequences are conditional whereas others require the composed parts to all be sendable to satisfy a requirement of `Sendable`. The effects are [listed here](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Effects.md).

## Adding Swift Async Algorithms as a Dependency

To use the `AsyncAlgorithms` library in a SwiftPM project, 
add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
```

Include `"AsyncAlgorithms"` as a dependency for your executable target:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
]),
```

Finally, add `import AsyncAlgorithms` to your source code.

## Getting Started

⚠️ Please note that this package requires Xcode 14 on macOS hosts. Previous versions of Xcode do not contain the required Swift version.

### Building/Testing Using Xcode on macOS

  1. In the `swift-async-algorithms` directory run `swift build` or `swift test` accordingly

### Building/Testing on Linux

  1. Download the most recent development toolchain for your Linux distribution
  2. Decompress the archive to a path in which the `swift` executable is in the binary search path environment variable (`$PATH`)
  3. In the `swift-async-algorithms` directory run `swift build` or `swift test` accordingly

## Source Stability

The Swift Async Algorithms package has a goal of being source stable as soon as possible; version numbers will follow [Semantic Versioning](https://semver.org/). Source breaking changes to public API can only land in a new major version.

The public API of version 1.0 of the `swift-async-algorithms` package will consist of non-underscored declarations that are marked `public` in the `AsyncAlgorithms` module. Interfaces that aren't part of the public API may continue to change in any release, including patch releases.

Future minor versions of the package may introduce changes to these rules as needed.

We'd like this package to quickly embrace Swift language and toolchain improvements that are relevant to its mandate. Accordingly, from time to time, we expect that new versions of this package will require clients to upgrade to a more recent Swift toolchain release. Requiring a new Swift release will only require a minor version bump.

# swift-async-algorithms

**Swift Async Algorithms** is an open-source package of asynchronous sequence and advanced algorithms that involve concurrency, along with their related types.

## Contents

#### Combining asynchronous sequences

- [`chain(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/Chain.md): Concatenates two or more asynchronous sequences with the same element type. 
- [`combineLatest(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/CombineLatest.md): Combines two or more asynchronous sequences into an asynchronous sequence producing a tuple of elements from those base asynchronous sequences that updates when any of the base sequences produce a value.
- [`merge(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Merges two or more asynchronous sequence into a single asynchronous sequence producing the elements of all of the underlying asynchronous sequences.
- [`zip(_:...)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Creates an asynchronous sequence of pairs built out of underlying asynchronous sequences.

#### Creating asynchronous sequences

- [`async`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/Lazy.md): Create an asynchronous sequence composed from a synchronous sequence.

#### Other useful asynchronous sequences
- [`joined(separator:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Concatenated elements of an asynchronous sequence of asynchronous sequences, inserting the given separator between each element.
- [`compacted()`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Remove nil values from an asynchronous sequence.
- [`removeDuplicates()`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Remove sequentially adjacent duplicate values.
- [`interspersed(with:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Place a value between every two elements of an asynchronous sequence.

#### Obtaining all values from an asynchronous sequence

- [`RangeReplaceableCollection.init(_:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Creates a new instance of a collection containing the elements of an asynchronous sequence.
- [`Dictionary.init(uniqueKeysWithValues:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Creates a new dictionary from the key-value pairs in the given asynchronous sequence.
- [`Dictionary.init(_:uniquingKeysWith:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Creates a new dictionary from the key-value pairs in the given asynchronous sequence, using a combining closure to determine the value for any duplicate keys.
- [`Dictionary.init(grouping:by:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/):   /// Creates a new dictionary whose keys are the groupings returned by the given closure and whose values are arrays of the elements that returned each key.
- [`SetAlgebra.init(_:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Creates a new set from an asynchronous sequence of items.
  

#### Task management

- [`Task.select(_:)`](https://github.com/apple/swift-async-algorithms/blob/main/Guides/): Determine the first task to complete of a sequence of tasks.

#### 

## Adding Swift Algorithms as a Dependency

To use the `AsyncAlgorithms` library in a SwiftPM project, 
add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/apple/swift-async-algorithms"),
```

Include `"AsyncAlgorithms"` as a dependency for your executable target:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
]),
```

Finally, add `import AsyncAlgorithms` to your source code.

## Source Stability

The Swift Async Algorithms package has a goal of being source stable as soon as possible; version numbers will follow [Semantic Versioning](https://semver.org/). Source breaking changes to public API can only land in a new major version.

The public API of version 1.0 of the `swift-async-algorithms` package will consist of non-underscored declarations that are marked `public` in the `AsyncAlgorithms` module. Interfaces that aren't part of the public API may continue to change in any release, including patch releases.

Future minor versions of the package may introduce changes to these rules as needed.

We'd like this package to quickly embrace Swift language and toolchain improvements that are relevant to its mandate. Accordingly, from time to time, we expect that new versions of this package will require clients to upgrade to a more recent Swift toolchain release. Requiring a new Swift release will only require a minor version bump.

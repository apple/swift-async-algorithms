# Collection Initializers

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Dictionary.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/RangeReplaceableCollection.swift),
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/SetAlgebra.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestDictionary.swift),
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestRangeReplaceableCollection.swift),
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestSetAlgebra.swift),
]


## Introduction

`Array`, `Dictionary` and `Set` are some of the most commonly-used data structures for storing collections of elements. Having a way to transition from an `AsyncSequence` to a collection is not only a useful shorthand but a powerful way of expressing direct intent for how to consume an `AsyncSequence`.

This type of functionality can be useful for examples and testing, and also for interfacing with existing APIs that expect a fully-formed collection before processing it.

## Proposed Solution

Three categories of initializers will be added to provide initializers for those three primary types: `Array`, `Dictionary` and `Set`. However these initializers can be written in a generic fashion such that they can apply to all similar collections.

`RangeReplaceableCollection` will gain a new initializer that constructs a collection given an `AsyncSequence`. This will allow for creating arrays from asynchronous sequences but also allow for creating types like `Data` or `ContiguousArray`. Because of the nature of asynchronous sequences, this initializer must be asynchronous and declare that it rethrows errors from the base asynchronous sequence.

```swift
extension RangeReplaceableCollection {
  public init<Source: AsyncSequence>(
    _ source: Source
  ) async rethrows 
    where Source.Element == Element
}
```

`Dictionary` will gain a family of new asynchronous, rethrowing initializers to parallel the existing `Sequence`-based initializers. The initializers will be asynchronous to facilitate uniquing keys and other tasks that may be asynchronous, in addition to the asynchronous initialization of the dictionaries.

```swift
extension Dictionary {
  public init<S: AsyncSequence>(
    uniqueKeysWithValues keysAndValues: S
  ) async rethrows 
    where S.Element == (Key, Value)
    
  public init<S: AsyncSequence>(
    _ keysAndValues: S, 
    uniquingKeysWith combine: (Value, Value) async throws -> Value
  ) async rethrows
    where S.Element == (Key, Value)
    
  public init<S: AsyncSequence>(
    grouping values: S, 
    by keyForValue: (S.Element) async throws -> Key
  ) async rethrows
    where Value == [S.Element]
}
```

`SetAlgebra` will gain a new asynchronous, rethrowing initializer that constructs a `SetAlgebra` type given an `AsyncSequence`. This will allow for creating sets from asynchronous sequences and allow for creating types like `OptionSet` types or `IndexSet`.

```swift
extension SetAlgebra {
  public init<Source: AsyncSequence>(
    _ source: Source
  ) async rethrows
    where Source.Element == Element
}
```

## Detailed Design

Each of the initializers is intended for uses where the `AsyncSequence` being used for initialization is known to be finite. Common uses include: 

* Reading from files via the `AsyncBytes` style sequences or `lines` accessors.
* Gathering elements produced by a `TaskGroup`.
* Accessing a prefix of an indefinite `AsyncSequence`. 

Each of the initializers will use the `for`-`await`-`in`/`for`-`try`-`await`-`in` syntax to iterate the sequence directly in the initializer. In addition each initializer relies on the `AsyncSequence` being passed in to properly respect cancellation. In the cases where cancellation is a potential, developers should be ready to either check immediately or be ready for initialization based on a partial sequence, depending on the behavior of the `AsyncSequence` being used. 

### RangeReplaceableCollection

```swift
let contents = try await Data(URL(fileURLWithPath: "/tmp/example.bin").resourceBytes)
```

### Dictionary

```swift
let table = await Dictionary(uniqueKeysWithValues: zip(keys, values))
```

### SetAlgebra

```swift
let allItems = await Set(items.prefix(10))
```

## Alternatives Considered

The spelling of these initializers could be expressed as a trailing conversion. However, that can lead to hard-to-read chains of operations. Functionally these all belong to the `reduce` family of functions, but due to source readability concerns they are more ergonomic for understanding what the code does by using the initializer patterns.

## Credits/Inspiration

The direct inspiration for each initialization is from their standard library counterparts. 

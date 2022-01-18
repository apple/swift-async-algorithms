# AsyncLazySequence

[[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncLazySequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestLazy.swift)]

Converts a non asynchronous sequence into an asynchronous one. 

This operation is available for all `Sequence` types. 

```swift
let numbers = [1, 2, 3, 4].async
let characters = "abcde".async
```

This transformation can be useful to test operations specifically available on `AsyncSequence` but also is useful 
to combine with other `AsyncSequence` types to provide well known sources of data. 

## Detailed Design

The `.async` property is returns an `AsyncLazySequence` that is generic upon the base `Sequence` it was constructed from.

```swift
extension Sequence {
  public var async: AsyncLazySequence<Self> { get }
}

public struct AsyncLazySequence<Base: Sequence>: AsyncSequence {
  ...
}

extension AsyncLazySequence: Sendable where Base: Sendable { }
extension AsyncLazySequence.Iterator: Sendable where Base.Iterator: Sendable { }

extension AsyncLazySequence: Codable where Base: Codable { }

extension AsyncLazySequence: Equatable where Base: Equatable { }

extension AsyncLazySequence: Hashable where Base: Hashable { }
```

The resulting `AsyncLazySequence` is an `AsyncSequence`, with conditional conformance to `Sendable`, `Codable`, `Equatable`, 
and `Hashable` when the base type conforms to these protocols.


### Naming

This property's and type's name match the naming approaches in the Swift standard library. The property is named with a 
succinct name in inspiration from `.lazy`, and the type is named in reference to the lazy behavior of the constructed 
`AsyncSequence`. 

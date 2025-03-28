# AsyncSyncSequence

This operation is available for all `Sequence` types. 

[[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncSyncSequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestLazy.swift)]

```swift
let numbers = [1, 2, 3, 4].async
let characters = "abcde".async
```

This transformation can be useful to test operations specifically available on `AsyncSequence` but also is useful 
to combine with other `AsyncSequence` types to provide well known sources of data. 

## Detailed Design

The `.async` property returns an `AsyncSyncSequence` that is generic upon the base `Sequence` it was constructed from.

```swift
extension Sequence {
  public var async: AsyncSyncSequence<Self> { get }
}

public struct AsyncSyncSequence<Base: Sequence>: AsyncSequence {
  ...
}

extension AsyncSyncSequence: Sendable where Base: Sendable { }
extension AsyncSyncSequence.Iterator: Sendable where Base.Iterator: Sendable { }
```

### Naming

This property's and type's name match the naming approaches in the Swift standard library. The property is named with a 
succinct name in inspiration from `.lazy`, and the type is named in reference to the lazy behavior of the constructed 
`AsyncSequence`. 

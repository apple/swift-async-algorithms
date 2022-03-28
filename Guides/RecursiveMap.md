# RecursiveMap

* Author(s): [Susan Cheng](https://github.com/SusanDoggie)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncRecursiveMapSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestRecursiveMap.swift)
]

Produces a sequence containing the original sequence followed by recursive mapped sequence.

```swift
struct View {
    var id: Int
    var children: [View] = []
}
let tree = [
    View(id: 1, children: [
        View(id: 3),
        View(id: 4, children: [
            View(id: 6),
        ]),
        View(id: 5),
    ]),
    View(id: 2),
]
for await view in tree.async.recursiveMap({ $0.children.async }) {
    print(view.id)
}
// 1
// 2
// 3
// 4
// 5
// 6
```

## Detailed Design

The `recursiveMap(_:)` method is declared as `AsyncSequence` extensions, and return `AsyncRecursiveMapSequence` or `AsyncThrowingRecursiveMapSequence` instance:

```swift
extension AsyncSequence {
    public func recursiveMap<S>(
        _ transform: @Sendable @escaping (Element) async -> S
    ) -> AsyncRecursiveMapSequence<Self, S>
    
    public func recursiveMap<S>(
        _ transform: @Sendable @escaping (Element) async throws -> S
    ) -> AsyncThrowingRecursiveMapSequence<Self, S>
}
```

### Complexity

Calling this method is O(_1_).

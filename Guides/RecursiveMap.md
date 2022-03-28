# RecursiveMap

* Author(s): [Susan Cheng](https://github.com/SusanDoggie)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncRecursiveMapSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestRecursiveMap.swift)
]

Produces a sequence containing the original sequence followed by recursive mapped sequence.

```swift
struct Node {
    var id: Int
    var children: [Node] = []
}
let tree = [
    Node(id: 1, children: [
        Node(id: 3),
        Node(id: 4, children: [
            Node(id: 6),
        ]),
        Node(id: 5),
    ]),
    Node(id: 2),
]
for await node in tree.async.recursiveMap({ $0.children.async }) {
    print(node.id)
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

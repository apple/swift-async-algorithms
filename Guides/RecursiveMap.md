# RecursiveMap

* Author(s): [Susan Cheng](https://github.com/SusanDoggie)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncRecursiveMapSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestRecursiveMap.swift)
]

## Proposed Solution

Produces a sequence containing the original sequence and the recursive mapped sequence. The order of ouput elements affects by the traversal option.

```swift
struct Node {
    var id: Int
    var children: [Node] = []
}
let tree = [
    Node(id: 1, children: [
        Node(id: 2),
        Node(id: 3, children: [
            Node(id: 4),
        ]),
        Node(id: 5),
    ]),
    Node(id: 6),
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

### Traversal Option

This function comes with two different traversal methods. This option affects the element order of the output sequence.

- `depthFirst`: The algorithm will go down first and produce the resulting path. The algorithm starts with original 
  sequence and calling the supplied closure first. This is default option.
  
  With the structure of tree:
  ```swift
  let tree = [
      Node(id: 1, children: [
          Node(id: 2),
          Node(id: 3, children: [
              Node(id: 4),
          ]),
          Node(id: 5),
      ]),
      Node(id: 6),
  ]
  ```
  
  The resulting sequence will be 1 -> 2 -> 3 -> 4 -> 5 -> 6

- `breadthFirst`: The algorithm will go through the previous sequence first and chaining all the occurring sequences.

  With the structure of tree:
  ```swift
  let tree = [
      Node(id: 1, children: [
          Node(id: 2),
          Node(id: 3, children: [
              Node(id: 4),
          ]),
          Node(id: 5),
      ]),
      Node(id: 6),
  ]
  ```
  
  The resulting sequence will be 1 -> 6 -> 2 -> 3 -> 5 -> 4

## Detailed Design

The `recursiveMap(option:_:)` method is declared as `AsyncSequence` extensions, and return `AsyncRecursiveMapSequence` or `AsyncThrowingRecursiveMapSequence` instance:

```swift
extension AsyncSequence {
    public func recursiveMap<S>(
        option: AsyncRecursiveMapSequence<Self, S>.TraversalOption = .depthFirst,
        _ transform: @Sendable @escaping (Element) async -> S
    ) -> AsyncRecursiveMapSequence<Self, S>
    
    public func recursiveMap<S>(
        option: AsyncThrowingRecursiveMapSequence<Self, S>.TraversalOption = .depthFirst,
        _ transform: @Sendable @escaping (Element) async throws -> S
    ) -> AsyncThrowingRecursiveMapSequence<Self, S>
}
```

For the non-throwing recursive map sequence, `AsyncRecursiveMapSequence` will throw only if the base sequence or the transformed sequence throws. As the opposite side, `AsyncThrowingRecursiveMapSequence` throws when the base sequence, tarnsformed sequence or the supplied closure throws.

The sendability behavior of `Async[Throwing]RecursiveMapSequence` is such that when the base, base iterator, and element are `Sendable` then `Async[Throwing]RecursiveMapSequence` is `Sendable`.

### Complexity

Calling this method is O(_1_).

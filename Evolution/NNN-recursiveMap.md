# recursiveMap

* Proposal: [NNNN](NNNN-filename.md)
* Authors: [SusanDoggie](https://github.com/SusanDoggie)
* Review Manager: TBD
* Status: **Awaiting implementation**
* Implementation: [apple/swift-async-algorithms#NNNNN](https://github.com/apple/swift-async-algorithms/pull/118)

## Introduction

Bring SQL's recursive CTE like operation to Swift. This method traverses all nodes of the tree and produces a flat sequence.

Swift forums thread: [Discussion thread topic for that proposal](https://forums.swift.org/)

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
  
  The sequence using a buffer keep tracking the path of nodes. It should not using this option for searching the indefinite deep of tree.

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
  
  The sequence using a buffer storing occuring nodes of sequences. It should not using this option for searching the indefinite length of occuring sequences.

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

For the non-throwing recursive map sequence, `AsyncRecursiveMapSequence` will throw only if the base sequence or the transformed sequence throws. As the opposite side, `AsyncThrowingRecursiveMapSequence` throws when the base sequence, the transformed sequence or the supplied closure throws.

The sendability behavior of `Async[Throwing]RecursiveMapSequence` is such that when the base, base iterator, and element are `Sendable` then `Async[Throwing]RecursiveMapSequence` is `Sendable`.

### Complexity

Calling this method is O(_1_).

## Effect on API resilience

none.

## Alternatives considered

none.

## Acknowledgments

none.

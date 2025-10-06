# Intersperse

Places a given value in between each element of the asynchronous sequence.

[[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/Interspersed/AsyncInterspersedSequence.swift) | 
 [Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/Interspersed/TestInterspersed.swift)]

```swift
let numbers = [1, 2, 3].async.interspersed(with: 0)
for await number in numbers {
  print(number)
}
// prints 1 0 2 0 3

let empty = [].async.interspersed(with: 0)
// await Array(empty) == []
```

`interspersed(with:)` takes a separator value and inserts it in between every
element in the asynchronous sequence.

## Detailed Design

A new method is added to `AsyncSequence`:

```swift
extension AsyncSequence {
  func interspersed(with separator: Element) -> AsyncInterspersedSequence<Self>
}
```

The new `AsyncInterspersedSequence` type represents the asynchronous sequence 
when the separator is inserted between each element. 

When the base asynchronous sequence can throw on iteration, `AsyncInterspersedSequence`
will throw on iteration. When the base does not throw, the iteration of 
`AsyncInterspersedSequence` does not throw either.

`AsyncInterspersedSequence` is conditionally `Sendable` when the base asynchronous
sequence is `Sendable` and the element is also `Sendable`.

### Naming

This method’s and type’s name match the term of art used in other languages
and libraries.

This method is a direct analog to the synchronous version [defined in the Swift Algorithms package](https://github.com/apple/swift-algorithms/blob/main/Guides/Intersperse.md).

### Comparison with other languages

**[Haskell][Haskell]:** Has an `intersperse` function which takes an element
and a list and 'intersperses' that element between the elements of the list.

**[Rust][Rust]:** Has a function called `intersperse` to insert a particular
value between each element. 

<!-- Link references for other languages -->

[Haskell]: https://hackage.haskell.org/package/base-4.14.0.0/docs/Data-List.html#v:intersperse
[Rust]: https://docs.rs/itertools/0.9.0/itertools/trait.Itertools.html#method.intersperse

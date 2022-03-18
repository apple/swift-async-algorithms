# ``AsyncAlgorithms``

An open-source package of asynchronous sequence and advanced algorithms that involve concurrency, along with their related types.

This package has three main goals:

- First-class integration with `async/await`
- Provide a home for time-based algorithms
- Be cross-platform and open source

AsyncAlgorithms is a package for algorithms that work with *values over time*. That includes those primarily about *time*, like `debounce` and `throttle`, but also algorithms about *order* like `combineLatest` and `merge`. Operations that work with multiple inputs (like `zip` does on `Sequence`) can be surprisingly complex to implement, with subtle behaviors and many edge cases to consider. A shared package can get these details correct, with extensive testing and documentation, for the benefit of all Swift apps.

The foundation for AsyncAlgorithms was included in Swift 5.5 from [AsyncSequence](https://github.com/apple/swift-evolution/blob/main/proposals/0298-asyncsequence.md). Swift 5.5 also brings the ability to use a natural `for/in` loop with `await` to process the values in an `AsyncSequence` and `Sequence`-equivalent API like `map` and `filter`. Structured concurrency allows us to write code where intermediate state is simply a local variable, `try` can be used directly on functions that `throw`, and generally treat the logic for asynchronous code similar to that of synchronous code.

This package is the home for these APIs. Development and API design take place on [GitHub](https://github.com/apple/swift-async-algorithms) and the [Swift Forums](https://forums.swift.org/c/related-projects/).

## Topics

### AsyncSequence Extensions

- <doc:Buffer>
- <doc:Chunk>
- <doc:Compacted>
- <doc:Debounce>
- <doc:Intersperse>
- <doc:Join>
- <doc:Reductions>
- <doc:RemoveDuplicates>
- <doc:Throttle>

### Task Extensions

- <doc:Task-Extensions>

### Functions

- ``AsyncAlgorithms/chain(_:_:)``
- ``AsyncAlgorithms/chain(_:_:_:)``
- ``AsyncAlgorithms/combineLatest(_:_:)``
- ``AsyncAlgorithms/combineLatest(_:_:_:)``
- ``AsyncAlgorithms/merge(_:_:)``
- ``AsyncAlgorithms/merge(_:_:_:)``
- ``AsyncAlgorithms/zip(_:_:)``
- ``AsyncAlgorithms/zip(_:_:_:)``

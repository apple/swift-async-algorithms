# ``AsyncAlgorithms``

**Swift Async Algorithms** is an open-source package of asynchronous sequence and advanced algorithms that involve concurrency, along with their related types.

This package has three main goals:

- First-class integration with `async/await`
- Provide a home for time-based algorithms
- Be cross-platform and open source

AsyncAlgorithms is a package for algorithms that work with *values over time*. That includes those primarily about *time*, like `debounce` and `throttle`, but also algorithms about *order* like `combineLatest` and `merge`. Operations that work with multiple inputs (like `zip` does on `Sequence`) can be surprisingly complex to implement, with subtle behaviors and many edge cases to consider. A shared package can get these details correct, with extensive testing and documentation, for the benefit of all Swift apps.

The foundation for AsyncAlgorithms was included in Swift 5.5 from [AsyncSequence](https://github.com/apple/swift-evolution/blob/main/proposals/0298-asyncsequence.md). Swift 5.5 also brings the ability to use a natural `for/in` loop with `await` to process the values in an `AsyncSequence` and `Sequence`-equivalent API like `map` and `filter`. Structured concurrency allows us to write code where intermediate state is simply a local variable, `try` can be used directly on functions that `throw`, and generally treat the logic for asynchronous code similar to that of synchronous code.

This package is the home for these APIs. Development and API design take place on [GitHub](https://github.com/apple/swift-async-algorithms) and the [Swift Forums](https://forums.swift.org/c/related-projects/).

## Topics

### AsyncSequence Extensions

- ``_Concurrency/AsyncSequence/buffer(_:)``
- ``_Concurrency/AsyncSequence/buffer(policy:)``
- ``_Concurrency/AsyncSequence/chunked(by:)-22u15``
- ``_Concurrency/AsyncSequence/chunked(by:)-6ueqa``
- ``_Concurrency/AsyncSequence/chunked(by:)-8r64n``
- ``_Concurrency/AsyncSequence/chunked(by:into:)-15i9z``
- ``_Concurrency/AsyncSequence/chunked(by:into:)-8x981``
- ``_Concurrency/AsyncSequence/chunked(into:by:)``
- ``_Concurrency/AsyncSequence/chunked(into:on:)``
- ``_Concurrency/AsyncSequence/chunked(on:)``
- ``_Concurrency/AsyncSequence/chunks(ofcount:)``
- ``_Concurrency/AsyncSequence/chunks(ofcount:into:)``
- ``_Concurrency/AsyncSequence/chunks(ofcount:or:)-1mvvt``
- ``_Concurrency/AsyncSequence/chunks(ofcount:or:)-9g3dr``
- ``_Concurrency/AsyncSequence/chunks(ofcount:or:into:)-8pp6q``
- ``_Concurrency/AsyncSequence/chunks(ofcount:or:into:)-8xk6u``
- ``_Concurrency/AsyncSequence/compacted()``
- ``_Concurrency/AsyncSequence/debounce(for:tolerance:)``
- ``_Concurrency/AsyncSequence/debounce(for:tolerance:clock:)``
- ``_Concurrency/AsyncSequence/interspersed(with:)``
- ``_Concurrency/AsyncSequence/joined(separator:)``
- ``_Concurrency/AsyncSequence/reductions(_:)-4efsu``
- ``_Concurrency/AsyncSequence/reductions(_:)-58t9p``
- ``_Concurrency/AsyncSequence/reductions(_:_:)-50jy3``
- ``_Concurrency/AsyncSequence/reductions(_:_:)-8lxv9``
- ``_Concurrency/AsyncSequence/reductions(into:_:)-1ghas``
- ``_Concurrency/AsyncSequence/reductions(into:_:)-t4an``
- ``_Concurrency/AsyncSequence/removeduplicates()``
- ``_Concurrency/AsyncSequence/removeduplicates(by:)-6epc2``
- ``_Concurrency/AsyncSequence/removeduplicates(by:)-7geff``
- ``_Concurrency/AsyncSequence/throttle(for:clock:latest:)``
- ``_Concurrency/AsyncSequence/throttle(for:clock:reducing:)``
- ``_Concurrency/AsyncSequence/throttle(for:latest:)``
- ``_Concurrency/AsyncSequence/throttle(for:reducing:)``

### Functions

- ``AsyncAlgorithms/chain(_:_:)``
- ``AsyncAlgorithms/chain(_:_:_:)``
- ``AsyncAlgorithms/combineLatest(_:_:)``
- ``AsyncAlgorithms/combineLatest(_:_:_:)``
- ``AsyncAlgorithms/merge(_:_:)``
- ``AsyncAlgorithms/merge(_:_:_:)``
- ``AsyncAlgorithms/zip(_:_:)``
- ``AsyncAlgorithms/zip(_:_:_:)``

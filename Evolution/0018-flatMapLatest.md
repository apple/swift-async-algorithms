# FlatMapLatest

* Proposal: [SAA-00nn](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/00nn-flatMapLatest.md)
* Author(s): [Peter Friese](https://github.com/peterfriese)
* Status: **Proposed**
* Implementation: 
[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/FlatMapLatest/AsyncFlatMapLatestSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestFlatMapLatest.swift)
]
* Decision Notes:
* Bugs:

## Introduction

When transforming elements of an asynchronous sequence into new asynchronous sequences, there are cases where only the results from the most recent transformation are relevant, and previous transformations should be abandoned. This is particularly common in reactive user interfaces where rapid user input triggers asynchronous operations, but only the result of the latest operation matters.

## Motivation

Consider a search-as-you-type interface where each keystroke triggers a network request:

```swift
let searchQueries = userInputField.textChanges

// Without flatMapLatest - all requests complete, wasting resources
for await query in searchQueries {
  let results = try await searchAPI(query)
  displayResults(results) // May display stale results
}
```

Without automatic cancellation, earlier requests continue to completion even though their results are no longer relevant. This wastes network bandwidth, server resources, and may display stale results to the user if a slower request completes after a faster one.

The `flatMapLatest` operator solves this by automatically cancelling iteration on the previous inner sequence whenever a new element arrives from the outer sequence:

```swift
let searchResults = searchQueries.flatMapLatest { query in
  searchAPI(query)
}

for await result in searchResults {
  displayResults(result) // Only latest results displayed
}
```

This pattern is broadly applicable:
- **Location-based queries**: Cancel previous location lookups when user moves
- **Dynamic configuration**: Restart data loading when settings change
- **Auto-save**: Only save the most recent changes when user types rapidly
- **Real-time data**: Switch to new data streams based on user selections

## Proposed Solution

The `flatMapLatest` algorithm transforms each element from the base `AsyncSequence` into a new inner `AsyncSequence` using a transform closure. When a new element is produced by the base sequence, iteration on the current inner sequence is cancelled, and iteration begins on the newly created sequence.

The interface is available on all `AsyncSequence` types where both the base and inner sequences are `Sendable` along with two disfavored refinements to account for variations of typed throws signatures:

```swift
extension AsyncSequence where Self: Sendable {
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> some AsyncSequence<T.Element, T.Failure> & Sendable where T.Failure == Failure, T.Element: Sendable, Element: Sendable

  @_disfavoredOverload
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> some AsyncSequence<T.Element, Failure> & Sendable where T.Failure == Never, T.Element: Sendable, Element: Sendable

  @_disfavoredOverload
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> some AsyncSequence<T.Element, T.Failure> & Sendable where Failure == Never, T.Element: Sendable, Element: Sendable
}
```

This provides a clean API for expressing switching behavior:

```swift
userActions.flatMapLatest { action in
  performAction(action)
}
```

## Detailed Design

The type that implements the algorithm emits elements from the inner sequences. It throws when either the base type or any inner sequence throws.

Since both the base sequence and inner sequences must be `Sendable` (to support concurrent iteration and cancellation), `AsyncFlatMapLatestSequence` is unconditionally `Sendable`.

### Implementation Strategy

The implementation uses a state machine pattern to ensure thread-safe operation:

1. **Generation Tracking**: Each new inner sequence is assigned a generation number. Elements from stale generations are discarded.
2. **Explicit Cancellation**: When a new outer element arrives, the previous inner sequence's task is explicitly cancelled and its continuation is resumed with a cancellation error.
3. **Lock-Based Coordination**: A `Lock` protects the state machine from concurrent access.
4. **Continuation Management**: The storage manages continuations for both upstream (outer/inner sequences) and downstream (consumer) demand.

This approach eliminates race conditions where cancelled sequences could emit stale values.

### Behavioral Characteristics

**Switching**: When the base sequence produces a new element, the current inner sequence iteration is immediately cancelled. Any elements it would have produced are lost.

**Completion**: The sequence completes when:
1. The base sequence finishes producing elements, AND
2. The final inner sequence finishes producing elements

**Error Handling**: If either the base sequence or any inner sequence throws, the error is immediately propagated and all tasks are cancelled.

**Cancellation**: Cancelling the downstream iteration cancels both the base sequence iteration and the current inner sequence iteration.

## Example

```swift
let requests = AsyncStream<String> { continuation in
  continuation.yield("query1")
  try? await Task.sleep(for: .milliseconds(100))
  continuation.yield("query2")
  try? await Task.sleep(for: .milliseconds(100))
  continuation.yield("query3")
  continuation.finish()
}

let responses = requests.flatMapLatest { query in
  AsyncStream<String> { continuation in
    continuation.yield("\(query): loading")
    try? await Task.sleep(for: .milliseconds(50))
    continuation.yield("\(query): complete")
    continuation.finish()
  }
}

for await response in responses {
  print(response)
}
// Output (may vary due to timing):
// query1: loading
// query2: loading
// query3: loading
// query3: complete
```

In this example, the earlier queries (query1 and query2) are cancelled before they complete, so only query3 produces its complete response.

## Effect on API Resilience

This is an additive API. No existing systems are changed. The new types introduced are:
- `AsyncFlatMapLatestSequence<Base, Inner>`: The sequence type
- Associated private types for the state machine implementation

These types will be part of the ABI surface area.

## Alternatives Considered

### Alternative Names

**`switchMap`**: Used in ReactiveX, but "switch" in Swift has strong association with control flow statements.

**`switchToLatest`**: Combine's terminology, but `flatMapLatest` is more discoverable alongside other `map` variants.

**`flatMap(...).latest()`**: Requires a hypothetical `flatMap` first, adding complexity.

### Delivering All Elements

An alternative behavior would buffer elements from cancelled sequences and deliver them later. However, this contradicts the core purpose of "latest" semantics and would be better served by a different operator.

### No Automatic Cancellation

Requiring manual cancellation would place significant burden on developers and be error-prone. The automatic cancellation is the key value proposition.

### Shorthand version for async sequences of async sequences

Mimicing combine a shorthand extension of `switchToLatest` could be added as an extension when the base AsyncSequence's element conforms to AsyncSequence. The implementation of which is trivial:

```swift
extension AsyncSequence where Self: Sendable {
  func switchToLatest() -> some AsyncSequence<Element.Element, Failure> where Element: AsyncSequence, Element.Failure == Failure, Element.Element: Sendable, Element: Sendable {
    flatMapLatest { $0 }
  }

  @_disfavoredOverload
  func switchToLatest() -> some AsyncSequence<Element.Element, Failure> where Element: AsyncSequence, Element.Failure == Never, Element.Element: Sendable, Element: Sendable {
    flatMapLatest { $0 }
  }

  @_disfavoredOverload
  func switchToLatest() -> some AsyncSequence<Element.Element, Failure> where Element: AsyncSequence, Failure == Never, Element.Element: Sendable, Element: Sendable {
    flatMapLatest { $0 }
  }
}
```

## Comparison with Other Libraries

**ReactiveX**: ReactiveX has an [API definition of switchMap](https://reactivex.io/documentation/operators/flatmap.html) that performs the same operation for Observables, switching to the latest inner Observable.

**Combine**: Combine has an [API definition of switchToLatest()](https://developer.apple.com/documentation/combine/publisher/switchtolatest()) which subscribes to the most recent Publisher produced by an upstream Publisher of Publishers. `flatMapLatest` combines the map and switch operations into a single convenient operator.

**RxSwift**: RxSwift calls this operator `flatMapLatest`, which is the naming this proposal adopts.

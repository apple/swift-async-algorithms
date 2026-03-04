# FlatMapLatest

* Author(s): [Peter Friese](https://github.com/peterfriese)

Transforms elements into asynchronous sequences, emitting elements from only the most recent inner sequence.

[[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/FlatMapLatest/AsyncFlatMapLatestSequence.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestFlatMapLatest.swift)]

```swift
let searchQuery = AsyncStream<String> { continuation in
  // User types into search field
  continuation.yield("swi")
  try? await Task.sleep(for: .milliseconds(100))
  continuation.yield("swift")
  try? await Task.sleep(for: .milliseconds(100))
  continuation.yield("swift async")
  continuation.finish()
}

let searchResults = searchQuery.flatMapLatest { query in
  performSearch(query) // Returns AsyncSequence<SearchResult>
}

for try await result in searchResults {
  print(result) // Only shows results from "swift async"
}
```

## Introduction

When transforming elements of an asynchronous sequence into new asynchronous sequences, you often want to abandon previous sequences when new data arrives. This is particularly useful for scenarios like search-as-you-type, where each keystroke triggers a new search request and you only care about results from the most recent query.

The `flatMapLatest` operator solves this by cancelling iteration on the previous inner sequence whenever a new element arrives from the outer sequence.

## Proposed Solution

The `flatMapLatest` algorithm transforms each element from the base `AsyncSequence` into a new inner `AsyncSequence` using the provided `transform` closure. When a new element is produced by the base sequence, iteration on the current inner sequence is cancelled, and iteration begins on the newly created sequence.

```swift
extension AsyncSequence where Self: Sendable {
  public func flatMapLatest<T: AsyncSequence & Sendable>(
    _ transform: @escaping @Sendable (Element) -> T
  ) -> AsyncFlatMapLatestSequence<Self, T>
}
```

This creates a concise way to express switching behavior:

```swift
userInput.flatMapLatest { input in
  fetchDataFromNetwork(input)
}
```

In this case, each new user input cancels any ongoing network request and starts a fresh one, ensuring only the latest data is delivered.

## Detailed Design

The type that implements the algorithm emits elements from the inner sequences. It throws when either the base type or any inner sequence throws.

```swift
public struct AsyncFlatMapLatestSequence<Base: AsyncSequence & Sendable, Inner: AsyncSequence & Sendable>: AsyncSequence, Sendable 
  where Base.Element: Sendable, Inner.Element: Sendable {
  public typealias Element = Inner.Element
  
  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public func next() async throws -> Element?
  }
  
  public func makeAsyncIterator() -> Iterator
}
```

The implementation uses a state machine to ensure thread-safe operation and generation tracking to prevent stale values from cancelled sequences.

### Behavior

- **Switching**: When a new element arrives from the base sequence, the current inner sequence is cancelled immediately
- **Completion**: The sequence completes when the base sequence finishes and the final inner sequence completes
- **Error Handling**: Errors from either the base or inner sequences are propagated immediately
- **Cancellation**: Cancelling iteration cancels both the base and current inner sequence

## Use Cases

### Search as You Type

```swift
let searchField = AsyncStream<String> { continuation in
  // Emit search queries as user types
  continuation.yield("s")
  continuation.yield("sw")
  continuation.yield("swift")
}

let results = searchField.flatMapLatest { query in
  searchAPI(for: query)
}
```

Only the results for "swift" will be emitted, as earlier queries are cancelled.

### Location-Based Data

```swift
let locationUpdates = CLLocationManager.shared.locationUpdates

let nearbyPlaces = locationUpdates.flatMapLatest { location in
  fetchNearbyPlaces(at: location)
}
```

Each location update triggers a new search, cancelling any ongoing requests for previous locations.

### Dynamic Configuration

```swift
let settings = userSettingsStream

let data = settings.flatMapLatest { config in
  loadData(with: config)
}
```

When settings change, data loading is restarted with the new configuration.

## Comparison with Other Operators

**`map`**: Transforms elements synchronously without producing sequences.

**`flatMap`** (if it existed): Would emit elements from all inner sequences concurrently, not cancelling previous ones.

**`switchToLatest`** (Combine): Equivalent operator in Combine framework - `flatMapLatest` is the `AsyncSequence` equivalent.

## Comparison with Other Libraries

**ReactiveX** ReactiveX has an [API definition of switchMap](https://reactivex.io/documentation/operators/flatmap.html) which performs the same operation for Observables.

**Combine** Combine has an [API definition of switchToLatest()](https://developer.apple.com/documentation/combine/publisher/switchtolatest()) which flattens a publisher of publishers by subscribing to the most recent one.

# MapError

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncMapErrorSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestMapError.swift)
]

## Introduction

With [SE-0421](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0421-generalize-async-sequence.md), an `AsyncSequence` carries the type of the failure it can throw as an associated `Failure` type. That makes the error type part of the interface an asynchronous sequence exposes, and it means an API that vends an asynchronous sequence has to decide which errors its callers are expected to handle.

Composing sequences that come from different sources therefore runs into the same problem the synchronous world has: the failure type produced deep inside an implementation is rarely the failure type that should be visible at the boundary of a module.

## Proposed Solution

A `mapError(_:)` method transforms the failure of an asynchronous sequence, leaving its elements untouched. It is the error-side counterpart of `map(_:)`.

```swift
extension AsyncSequence {
  public func mapError<MappedError: Error>(
    _ transform: @Sendable @escaping (Self.Failure) -> MappedError
  ) -> some AsyncSequence<Self.Element, MappedError>

  public func mapError<MappedError: Error>(
    _ transform: @Sendable @escaping (Self.Failure) -> MappedError
  ) -> (some AsyncSequence<Self.Element, MappedError> & Sendable)
    where Self: Sendable, Self.Element: Sendable
}
```

This lets a module wrap the failures of the sequences it composes into an error type of its own:

```swift
struct ConnectionError: Error {
  let underlying: any Error
}

func messages() -> some AsyncSequence<Message, ConnectionError> {
  socket
    .lines
    .map(Message.init(parsing:))
    .mapError(ConnectionError.init(underlying:))
}
```

Because the transform receives the concrete `Failure` type of the base sequence, it can also be used to narrow an existing `any Error` failure down to a specific type, which restores typed throws for callers of the resulting sequence.

## Detailed Design

Two overloads are provided. The second one is chosen when both the base sequence and its element are `Sendable`, and additionally guarantees that the resulting sequence is `Sendable` so that it can cross isolation boundaries.

The returned sequence is opaque; only its `Element` and `Failure` types are part of the API. It forwards `next(isolation:)` to the base iterator and applies the transform to any error the base sequence throws. The transform is only invoked when the base sequence actually fails — it is never called for a sequence that finishes normally, and it is invoked at most once per iteration since a failure terminates the sequence.

The iterator is not `Sendable`, matching the other sequences in this package.

This algorithm requires a Swift 6.0 or later compiler.

## Effect on API resilience

This is an additive API.

## Credits/Inspiration

This is a direct analog of the `mapError(_:)` operator found in Combine, adapted to the typed failures of `AsyncSequence`.

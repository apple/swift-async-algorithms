# Map Error

* Proposal: [SAA-NNNN](NNNN-map-error.md)
* Authors: [Clive Liu](https://github.com/clive819) [Philippe Hausler](https://github.com/phausler)
* Review Manager: TBD
* Status: **Awaiting review**

## Introduction

Asynchronous sequences often particpate in carefully crafted systems of algorithms spliced together. Some of those algorithms require that both the element type and the failure type are the same as each-other. In order to line those types up for the element we have the map algorithm today, however there are other times at which when using more specific APIs that transforming the Failure type is needed.

## Motivation

The `mapError` function empowers developers to elegantly transform errors within asynchronous sequences, enhancing code readability and maintainability.

Building failure-type-safe versions of zip or other algorithms will need to require that the associated Failure types are the same. Having an effecient and easy to use transformation routine to adjust the failure-types is then key to delivering or interfacing with those failure-type-safe algorithms.

## Proposed solution

A new extension and type will be added to transform the failure-types of AsyncSequences.

## Detailed design

The method will be applied to all AsyncSequences via an extension with the function name of `mapError`. This is spiritually related to the `mapError` method on `Result` and similar in functionality to other frameworks' methods of the similar naming. This will not return an opaque result since the type needs to be refined for `Sendable`; in that the `AsyncMapERrorSequence` is only `Sendable` when the base `AsyncSequence` is `Sendable`.

```swift
extension AsyncSequence {
    public func mapError<MappedFailure: Error>(_ transform: @Sendable @escaping (Failure) async -> MappedFailure) -> AsyncMapErrorSequence<Element, MappedFailure>
}

public struct AsyncMapErrorSequence<Base: AsyncSequence, TransformedFailure: Error>: AsyncSequence { }

extension AsyncMapErrorSequence: Sendable where Base: Sendable { }

@available(*, unavailable)
extension AsyncMapErrorSequence.Iterator: Sendable {}
```

## Effect on API resilience

This cannot be back-deployed to 1.0 since it has a base requirement for the associated `Failure` and requires typed throws.

## Naming

The naming follows to current method naming of the Combine [mapError](https://developer.apple.com/documentation/combine/publisher/maperror(_:)) method and similarly the name of the method on `Result`

## Alternatives considered

It was initially considered that the return type would be opaque, however the only way to refine that as Sendable would be to have a disfavored overload; this ended up creating more ambiguity than it seemed worth.
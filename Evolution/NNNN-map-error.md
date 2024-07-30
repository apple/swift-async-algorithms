# Map Error

* Proposal: [SAA-NNNN](NNNN-map-error.md)
* Authors: [Clive Liu](https://github.com/clive819)
* Review Manager: TBD
* Status: **Awaiting review**

*During the review process, add the following fields as needed:*

* Implementation: [apple/swift-async-algorithms#324](https://github.com/apple/swift-async-algorithms/pull/324)
* Decision Notes: 
* Bugs: 

## Introduction

The `mapError` function empowers developers to elegantly transform errors within asynchronous sequences, enhancing code readability and maintainability.

```swift
extension AsyncSequence {

    public func mapError<MappedFailure: Error>(_ transform: @Sendable @escaping (Self.Failure) -> MappedFailure) -> some AsyncSequence<Self.Element, MappedFailure> {
        AsyncMapErrorSequence(base: self, transform: transform)
    }
}
```

## Detailed design

The function iterates through the elements of an `AsyncSequence` within a do-catch block. If an error is caught, it calls the `transform` closure to convert the error into a new type and then throws it.

```swift
struct AsyncMapErrorSequence<Base: AsyncSequence, MappedFailure: Error>: AsyncSequence {

    ...

    func makeAsyncIterator() -> Iterator {
        Iterator(
            base: base.makeAsyncIterator(),
            transform: transform
        )
    }
}

extension AsyncMapErrorSequence {

    struct Iterator: AsyncIteratorProtocol {

        typealias Element = Base.Element

        private var base: Base.AsyncIterator

        private let transform: @Sendable (Failure) -> MappedFailure

        init(
            base: Base.AsyncIterator,
            transform: @Sendable @escaping (Failure) -> MappedFailure
        ) {
            self.base = base
            self.transform = transform
        }

        mutating func next() async throws(MappedFailure) -> Element? {
            do {
                return try await base.next(isolation: nil)
            } catch {
                throw transform(error)
            }
        }

        mutating func next(isolation actor: isolated (any Actor)?) async throws(MappedFailure) -> Element? {
            do {
                return try await base.next(isolation: actor)
            } catch {
                throw transform(error)
            }
        }
    }
}

extension AsyncMapErrorSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
```

## Naming

The naming follows to current method naming of the Combine [mapError](https://developer.apple.com/documentation/combine/publisher/maperror(_:)) method.

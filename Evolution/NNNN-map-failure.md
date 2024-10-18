# Map Failure

* Proposal: [SAA-NNNN](NNNN-map-failure.md)
* Authors: [Clive Liu](https://github.com/clive819)
* Review Manager: TBD
* Status: **Awaiting review**

*During the review process, add the following fields as needed:*

* Implementation: [apple/swift-async-algorithms#324](https://github.com/apple/swift-async-algorithms/pull/324)
* Decision Notes: 
* Bugs: 

## Introduction

The `mapFailure` function empowers developers to elegantly transform errors within asynchronous sequences, enhancing code readability and maintainability.

```swift
extension AsyncSequence {

    public func mapFailure<MappedFailure: Error>(_ transform: @Sendable @escaping (Self.Failure) -> MappedFailure) -> some AsyncSequence<Self.Element, MappedFailure> {
        AsyncMapFailureSequence(base: self, transform: transform)
    }
}
```

## Detailed design

The function iterates through the elements of an `AsyncSequence` within a do-catch block. If an error is caught, it calls the `transform` closure to convert the error into a new type and then throws it.

```swift
struct AsyncMapFailureSequence<Base: AsyncSequence, MappedFailure: Error>: AsyncSequence {

    ...

    func makeAsyncIterator() -> Iterator {
        Iterator(
            base: base.makeAsyncIterator(),
            transform: transform
        )
    }
}

extension AsyncMapFailureSequence {

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

extension AsyncMapFailureSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
```

## Naming

Using `mapFailure` since `Failure` defines the type that can be thrown from an `AsyncSequence`.

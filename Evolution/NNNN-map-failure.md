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

The actual implementation is quite simple actually - it's just simple do-catch block and invoking the transform closure inside the catch block - so we'll focus more on implementation decisions with regard to the compiler and OS versions difference.

```swift
extension AsyncSequence {

#if compiler(>=6.0)
    /// Converts any failure into a new error.
    ///
    /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapFailure(_:)`` operator when you need to replace one error type with another.
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func mapFailure<MappedFailure: Error>(_ transform: @Sendable @escaping (Self.Failure) -> MappedFailure) -> some AsyncSequence<Self.Element, MappedFailure> {
        AsyncMapFailureSequence(base: self, transform: transform)
    }
#endif

    /// Converts any error into a new error.
    ///
    /// - Parameter transform: A closure that takes the error as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    @available(macOS, deprecated: 15.0, renamed: "mapFailure")
    @available(iOS, deprecated: 18.0, renamed: "mapFailure")
    @available(watchOS, deprecated: 11.0, renamed: "mapFailure")
    @available(tvOS, deprecated: 18.0, renamed: "mapFailure")
    @available(visionOS, deprecated: 2.0, renamed: "mapFailure")
    public func mapError<MappedError: Error>(_ transform: @Sendable @escaping (any Error) -> MappedError) -> AsyncMapErrorSequence<Self, MappedError> {
        .init(base: self, transform: transform)
    }
}
```

The compiler check is needed to ensure the code can be built on older Xcode versions (15 and below). `AsyncSequence.Failure` is only available in new SDK that ships with Xcode 16 that has the 6.0 compiler, we'd get this error without the compiler check `'Failure' is not a member type of type 'Self'`.

As to the naming `mapFailure` versus `mapError`, this is the trade off we have to make due to the lack of the ability to mark function as unavailable from certain OS version. The function signatures are the same, if the function names were the same, compiler will always choose the one with `any Error` instead of the one that has more specific error type.

`mapError` function returns a concrete type instead of `some AsyncSequence<Self.Element, MappedError>` because `AsyncSequence.Failure` is only available in newer OS versions, we cannot specify it in old versions. And because using an opaque type would render typed throws feature ineffective by erasing the type, thereby preventing the compiler from ensuring that the returned sequence matches our intended new type. The benefits of using typed throws for this specific case outweigh the exposure of the internal types.

```swift
#if compiler(>=6.0)
/// An asynchronous sequence that converts any failure into a new error.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct AsyncMapFailureSequence<Base: AsyncSequence, MappedFailure: Error>: AsyncSequence {

    typealias AsyncIterator = Iterator
    typealias Element = Base.Element
    typealias Failure = Base.Failure

    private let base: Base
    private let transform: @Sendable (Failure) -> MappedFailure

    init(
        base: Base,
        transform: @Sendable @escaping (Failure) -> MappedFailure
    ) {
        self.base = base
        self.transform = transform
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(
            base: base.makeAsyncIterator(),
            transform: transform
        )
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncMapFailureSequence {

    /// The iterator that produces elements of the map sequence.
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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncMapFailureSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
#endif
```

`AsyncMapErrorSequence` would have similar implementation except it uses `any Error` instead of the associated Failure type, and doesn't support typed throws if the compiler is less than 6.0.

## Naming

`mapError` follows to current method naming of the Combine [mapError](https://developer.apple.com/documentation/combine/publisher/mapError(_:)) method.

Using `mapFailure` since `Failure` defines the type that can be thrown from an `AsyncSequence`.

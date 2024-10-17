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

The mapError function empowers developers to elegantly transform errors within asynchronous sequences, enhancing code readability and maintainability.

```swift
extension AsyncSequence {

    public func mapError<ErrorType: Error>(_ transform: @Sendable @escaping (Self.Failure) -> ErrorType) -> AsyncMapErrorSequence<Self, ErrorType>

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
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func mapError<ErrorType: Error>(_ transform: @Sendable @escaping (Self.Failure) -> ErrorType) -> AsyncMapErrorSequence<Self, ErrorType>
#endif

    /// Converts any failure into a new error.
    ///
    /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    @available(macOS, deprecated: 15.0, renamed: "mapError")
    @available(iOS, deprecated: 18.0, renamed: "mapError")
    @available(watchOS, deprecated: 11.0, renamed: "mapError")
    @available(tvOS, deprecated: 18.0, renamed: "mapError")
    @available(visionOS, deprecated: 2.0, renamed: "mapError")
    public func mapAnyError<ErrorType: Error>(_ transform: @Sendable @escaping (any Error) -> ErrorType) -> AsyncMapAnyErrorSequence<Self, ErrorType>
}
```

The compiler check is needed to ensure the code can be built on older Xcode versions (15 and below). `AsyncSequence.Failure` is only available in new SDK that ships with Xcode 16 that has the 6.0 compiler, we'd get this error without the compiler check `'Failure' is not a member type of type 'Self'`.

As to the naming `mapError` versus `mapAnyError`, this is the trade off we have to make due to the lack of the ability to mark function as unavailable from certain OS version. The function signatures are the same, if the function names were the same, compiler will always choose the one with `any Error` instead of the one that has more specific error type.

This function returns a concrete type instead of `some AsyncSequence` because using an opaque type would render typed throws feature ineffective by erasing the type, thereby preventing the compiler from ensuring that the returned sequence matches our intended new type. The benefits of using typed throws for this specific case outweigh the exposure of the internal types.

```swift
/// An asynchronous sequence that converts any failure into a new error.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct AsyncMapErrorSequence<Base: AsyncSequence, ErrorType: Error>: AsyncSequence {

    public typealias AsyncIterator = Iterator
    public typealias Element = Base.Element

    private let base: Base
    private let transform: @Sendable (Base.Failure) -> ErrorType

    init(
        base: Base,
        transform: @Sendable @escaping (Base.Failure) -> ErrorType
    ) {
        self.base = base
        self.transform = transform
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(
            base: base.makeAsyncIterator(),
            transform: transform
        )
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncMapErrorSequence {

    /// The iterator that produces elements of the map sequence.
    public struct Iterator: AsyncIteratorProtocol {

        public typealias Element = Base.Element

        private var base: Base.AsyncIterator

        private let transform: @Sendable (Base.Failure) -> ErrorType

        init(
            base: Base.AsyncIterator,
            transform: @Sendable @escaping (Base.Failure) -> ErrorType
        ) {
            self.base = base
            self.transform = transform
        }


        public mutating func next() async throws(ErrorType) -> Element? {
            do {
                return try await base.next(isolation: nil)
            } catch {
                throw transform(error)
            }
        }

        public mutating func next(isolation actor: isolated (any Actor)?) async throws(ErrorType) -> Element? {
            do {
                return try await base.next(isolation: actor)
            } catch {
                throw transform(error)
            }
        }
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncMapErrorSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
```

`AsyncMapAnyErrorSequence` would have similar implementation except it uses `any Error` instead of the associated Failure type, and doesn't support typed throws if the compiler is less than 6.0.

## Naming

The naming follows to current method naming of the Combine [mapError](https://developer.apple.com/documentation/combine/publisher/maperror(_:)) method.

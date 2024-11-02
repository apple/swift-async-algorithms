//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.0)
extension AsyncSequence {

    /// Converts any failure into a new error.
    ///
    /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func mapError<MappedFailure: Error>(_ transform: @Sendable @escaping (Self.Failure) -> MappedFailure) -> some AsyncSequence<Self.Element, MappedFailure> {
        AsyncMapErrorSequence(base: self, transform: transform)
    }

    /// Converts any failure into a new error.
    ///
    /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func mapError<MappedFailure: Error>(_ transform: @Sendable @escaping (Self.Failure) -> MappedFailure) -> (some AsyncSequence<Self.Element, MappedFailure> & Sendable) where Self: Sendable, Self.Element: Sendable {
        AsyncMapErrorSequence(base: self, transform: transform)
    }
}

/// An asynchronous sequence that converts any failure into a new error.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
fileprivate struct AsyncMapErrorSequence<Base: AsyncSequence, MappedFailure: Error>: AsyncSequence {

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
extension AsyncMapErrorSequence {

    /// The iterator that produces elements of the map sequence.
    fileprivate struct Iterator: AsyncIteratorProtocol {

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
            try await self.next(isolation: nil)
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
extension AsyncMapErrorSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncMapErrorSequence.Iterator: Sendable {}
#endif

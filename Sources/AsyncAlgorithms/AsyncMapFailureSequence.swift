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

// MARK: - AsyncMapFailureSequence

#if compiler(>=6.0)
/// An asynchronous sequence that converts any failure into a new error.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
fileprivate struct AsyncMapFailureSequence<Base: AsyncSequence, MappedFailure: Error>: AsyncSequence {

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

// MARK: - AsyncMapErrorSequence

/// An asynchronous sequence that converts any failure into a new error.
public struct AsyncMapErrorSequence<Base: AsyncSequence, MappedError: Error>: AsyncSequence {

    public typealias AsyncIterator = Iterator
    public typealias Element = Base.Element

    private let base: Base
    private let transform: @Sendable (any Error) -> MappedError

    init(
        base: Base,
        transform: @Sendable @escaping (any Error) -> MappedError
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

extension AsyncMapErrorSequence {

    /// The iterator that produces elements of the map sequence.
    public struct Iterator: AsyncIteratorProtocol {

        public typealias Element = Base.Element

        private var base: Base.AsyncIterator

        private let transform: @Sendable (any Error) -> MappedError

        init(
            base: Base.AsyncIterator,
            transform: @Sendable @escaping (any Error) -> MappedError
        ) {
            self.base = base
            self.transform = transform
        }

#if compiler(>=6.0)
        public mutating func next() async throws(MappedError) -> Element? {
            do {
                return try await base.next()
            } catch {
                throw transform(error)
            }
        }

        @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
        public mutating func next(isolation actor: isolated (any Actor)?) async throws(MappedError) -> Element? {
            do {
                return try await base.next(isolation: actor)
            } catch {
                throw transform(error)
            }
        }
#else
        public mutating func next() async throws -> Element? {
            do {
                return try await base.next()
            } catch {
                throw transform(error)
            }
        }
#endif
    }
}

extension AsyncMapErrorSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

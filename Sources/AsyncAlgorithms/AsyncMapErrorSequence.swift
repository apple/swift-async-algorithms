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
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func mapError<ErrorType: Error>(_ transform: @Sendable @escaping (Self.Failure) -> ErrorType) -> AsyncMapErrorSequence<Self, ErrorType> {
        .init(base: self, transform: transform)
    }
#endif

    /// Converts any failure into a new error.
    ///
    /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapAnyError(_:)`` operator when you need to replace one error type with another.
    @available(macOS, deprecated: 15.0, renamed: "mapError")
    @available(iOS, deprecated: 18.0, renamed: "mapError")
    @available(watchOS, deprecated: 11.0, renamed: "mapError")
    @available(tvOS, deprecated: 18.0, renamed: "mapError")
    @available(visionOS, deprecated: 2.0, renamed: "mapError")
    public func mapAnyError<ErrorType: Error>(_ transform: @Sendable @escaping (any Error) -> ErrorType) -> AsyncMapAnyErrorSequence<Self, ErrorType> {
        .init(base: self, transform: transform)
    }
}

// MARK: - AsyncMapErrorSequence

#if compiler(>=6.0)
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
#endif

// MARK: - AsyncMapAnyErrorSequence

/// An asynchronous sequence that converts any failure into a new error.
public struct AsyncMapAnyErrorSequence<Base: AsyncSequence, ErrorType: Error>: AsyncSequence {

    public typealias AsyncIterator = Iterator
    public typealias Element = Base.Element

    private let base: Base
    private let transform: @Sendable (any Error) -> ErrorType

    init(
        base: Base,
        transform: @Sendable @escaping (any Error) -> ErrorType
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

extension AsyncMapAnyErrorSequence {

    /// The iterator that produces elements of the map sequence.
    public struct Iterator: AsyncIteratorProtocol {

        public typealias Element = Base.Element

        private var base: Base.AsyncIterator

        private let transform: @Sendable (any Error) -> ErrorType

        init(
            base: Base.AsyncIterator,
            transform: @Sendable @escaping (any Error) -> ErrorType
        ) {
            self.base = base
            self.transform = transform
        }

#if compiler(>=6.0)
        public mutating func next() async throws(ErrorType) -> Element? {
            do {
                return try await base.next()
            } catch {
                throw transform(error)
            }
        }

        @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
        public mutating func next(isolation actor: isolated (any Actor)?) async throws(ErrorType) -> Element? {
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

extension AsyncMapAnyErrorSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

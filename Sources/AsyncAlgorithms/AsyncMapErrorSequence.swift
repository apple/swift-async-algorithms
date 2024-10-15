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

    /// Converts any failure into a new error.
    ///
    /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    public func mapError<ErrorType>(transform: @Sendable @escaping (Error) -> ErrorType) -> AsyncMapErrorSequence<Self, ErrorType> {
        .init(base: self, transform: transform)
    }
}

/// An asynchronous sequence that converts any failure into a new error.
public struct AsyncMapErrorSequence<Base: AsyncSequence, ErrorType: Error>: AsyncSequence {

    public typealias AsyncIterator = Iterator
    public typealias Element = Base.Element

    private let base: Base
    private let transform: @Sendable (Error) -> ErrorType

    init(
        base: Base,
        transform: @Sendable @escaping (Error) -> ErrorType
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

        private let transform: @Sendable (Error) -> ErrorType

        init(
            base: Base.AsyncIterator,
            transform: @Sendable @escaping (Error) -> ErrorType
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

extension AsyncMapErrorSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

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

public extension AsyncSequence {

    /// Converts any failure into a new error.
    ///
    /// - Parameter transform: A closure that takes the failure as a parameter and returns a new error.
    /// - Returns: An asynchronous sequence that maps the error thrown into the one produced by the transform closure.
    ///
    /// Use the ``mapError(_:)`` operator when you need to replace one error type with another.
    func mapError<ErrorType>(transform: @Sendable @escaping (Error) -> ErrorType) -> AsyncMapErrorSequence<Self, ErrorType> {
        .init(base: self, transform: transform)
    }
}

/// An asynchronous sequence that converts any failure into a new error.
public struct AsyncMapErrorSequence<Base: AsyncSequence, ErrorType: Error>: AsyncSequence, Sendable where Base: Sendable {

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

public extension AsyncMapErrorSequence {
    
    /// The iterator that produces elements of the map sequence.
    struct Iterator: AsyncIteratorProtocol {

        public typealias Element = Base.Element

        private var base: Base.AsyncIterator

        private let transform: @Sendable (Error) -> ErrorType

        public init(
            base: Base.AsyncIterator,
            transform: @Sendable @escaping (Error) -> ErrorType
        ) {
            self.base = base
            self.transform = transform
        }

        public mutating func next() async throws -> Element? {
            do {
                return try await base.next()
            } catch {
                throw transform(error)
            }
        }
    }
}

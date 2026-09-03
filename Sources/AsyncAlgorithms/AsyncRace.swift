//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// Returns the value or throws an error, from the first completed or failed operation.
public func race(_ operations: (@Sendable () async throws -> Void)...) async throws {
    try await race(operations)
}

/// Returns the value or throws an error, from the first completed or failed operation.
public func race<T: Sendable>(_ operations: (@Sendable () async throws -> T)...) async throws -> T? {
    try await race(operations)
}

/// Returns the value or throws an error, from the first completed or failed operation.
public func race<T: Sendable>(_ operations: [@Sendable () async throws -> T]) async throws -> T? {
    try await withThrowingTaskGroup(of: T.self) { group in
        operations.forEach { operation in
            group.addTask { try await operation() }
        }
        defer {
            group.cancelAll()
        }
        return try await group.next()
    }
}

/// Returns the value or throws an error, from the first completed or failed operation.
public func race<T: Sendable>(_ operations: (@Sendable () async throws -> T?)...) async throws -> T? {
    try await race(operations)
}

/// Returns the value or throws an error, from the first completed or failed operation.
public func race<T: Sendable>(_ operations: [@Sendable () async throws -> T?]) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        operations.forEach { operation in
            group.addTask { try await operation() }
        }
        defer {
            group.cancelAll()
        }
        let value = try await group.next()
        switch value {
        case .none:
            return nil
        case let .some(value):
            return value
        }
    }
}

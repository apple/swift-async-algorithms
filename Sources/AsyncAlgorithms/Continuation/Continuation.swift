//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.3)
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@frozen
public struct Continuation<Success /*: ~Copyable*/, Failure: Error>: ~Copyable {

    @usableFromInline
    let unsafeContinuation: UnsafeContinuation<Success, Failure>
    @usableFromInline
    let file: StaticString
    @usableFromInline
    let line: Int

    @inlinable
    init(_ unsafeContinuation: UnsafeContinuation<Success, Failure>, file: StaticString, line: Int) {
        self.unsafeContinuation = unsafeContinuation
        self.file = file
        self.line = line
    }

    deinit {
        fatalError("The continuation created in \(self.file):\(self.line) was dropped.")
    }

    @inlinable
    consuming public func resume() where Success == Void {
        self.unsafeContinuation.resume()
        discard self // prevent deinit
    }

    @inlinable
    consuming public func resume(returning value: consuming sending Success) {
        self.unsafeContinuation.resume(returning: value)
        discard self // prevent deinit
    }

    @inlinable
    consuming public func resume(throwing error: Failure) {
        self.unsafeContinuation.resume(throwing: error)
        discard self // prevent deinit
    }

    @inlinable
    consuming public func resume(with result: consuming sending Result<Success, Failure>) {
        self.unsafeContinuation.resume(with: result)
        discard self // prevent deinit
    }
}

@inlinable
// TODO: Add the failure Never mode and the ~Copyable Success, once support for this is in the stdlib.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public nonisolated(nonsending) func withContinuation<Success/*: ~Copyable, Failure: Error*/>(
    of: Success.Type,
//    failure: Failure.Type,
    file: StaticString = #file,
    line: Int = #line,
    _ body: (consuming Continuation<Success, any Error>) -> Void
) async throws -> Success {
    try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Success, any Error>) in
        body(Continuation(continuation, file: file, line: line))
    }
}
#endif

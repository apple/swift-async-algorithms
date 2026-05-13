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

#if UnstableAsyncStreaming && compiler(>=6.4)

public import ContainersPreview

// swift-format-ignore: AmbiguousTrailingClosureOverload
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable {
  /// Iterates over all chunks from the reader, executing the provided body for each buffer.
  ///
  /// This method continuously reads chunks from the async reader until the stream ends,
  /// executing the provided closure for each buffer of elements read. The iteration terminates
  /// when the reader produces an empty buffer, indicating the end of the stream.
  ///
  /// - Parameter body: An asynchronous closure that processes each buffer of elements read
  ///   from the stream.
  ///
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
  ///   or a `Failure` from the body closure.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// try await fileReader.forEachBuffer { buffer in
  ///     print("Processing \(buffer.count) elements")
  /// }
  /// ```
  public consuming func forEachBuffer<Failure: Error>(
    body: (inout Buffer) async throws(Failure) -> Void
  ) async throws(EitherError<ReadFailure, Failure>) {
    var shouldContinue = true
    while shouldContinue {
      try await self.read { (next) throws(Failure) -> Void in
        guard next.count > 0 else {
          shouldContinue = false
          return
        }

        try await body(&next)
      }
    }
  }

  /// Iterates over all chunks from a non-failing reader, executing the provided body for each buffer.
  ///
  /// This method continuously reads chunks from the async reader until the stream ends,
  /// executing the provided closure for each buffer of elements read. The iteration terminates
  /// when the reader produces an empty buffer, indicating the end of the stream.
  ///
  /// Use this overload when the reader's ``AsyncReader/ReadFailure`` type is `Never`.
  ///
  /// - Parameter body: An asynchronous closure that processes each buffer of elements read
  ///   from the stream.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// await fileReader.forEachBuffer { buffer in
  ///     print("Processing \(buffer.count) elements")
  /// }
  /// ```
  @inlinable
  public consuming func forEachBuffer(
    body: (inout Buffer) async -> Void
  ) async where ReadFailure == Never {
    var shouldContinue = true
    while shouldContinue {
      do {
        try await self.read { (next) -> Void in
          guard next.count > 0 else {
            shouldContinue = false
            return
          }

          await body(&next)
        }
      } catch {
        fatalError()
      }
    }
  }
}
#endif

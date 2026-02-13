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

/// Reads elements asynchronously from a source.
///
/// Adopt ``AsyncReader`` when you need to provide callee-managed buffering,
/// where the reader controls the buffer and passes a span of elements
/// to the caller through the `body` closure.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, visionOS 1.0, *)
public protocol AsyncReader<ReadElement, ReadFailure>: ~Copyable, ~Escapable {
  /// The type of elements this reader reads.
  associatedtype ReadElement: ~Copyable

  /// The error type that reading operations throw.
  associatedtype ReadFailure: Error

  /// Reads elements from the underlying source and passes them to the provided body closure.
  ///
  /// This method asynchronously reads a span of elements from the source,
  /// then passes them to `body` for processing.
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// // Read data from a file asynchronously and process it.
  /// let result = try await fileReader.read { data in
  ///     guard data.count > 0 else {
  ///         return
  ///     }
  ///     return data
  /// }
  /// ```
  ///
  /// - Parameter maximumCount: The maximum count of items you're ready
  ///   to process. Must be greater than zero.
  /// - Parameter body: A closure that processes a span of read elements
  ///   and returns a value of type `Return`. When the span is empty,
  ///   it indicates the end of the stream.
  /// - Returns: The value the body closure returns after processing the read elements.
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
  ///   or a `Failure` from the body closure.
  mutating func read<Return, Failure: Error>(
    maximumCount: Int,
    body: (consuming InputSpan<ReadElement>) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return

}

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, visionOS 1.0, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable {
  /// Reads elements with no upper bound on span size.
  mutating func read<Return, Failure: Error>(
    body: (consuming InputSpan<ReadElement>) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return {
    try await read(maximumCount: .max, body: body)
  }
}
#endif

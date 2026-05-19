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

/// Reads elements asynchronously from a source using callee-managed buffering.
///
/// Adopt ``AsyncReader`` when you need callee-managed buffering,
/// where the reader controls the buffer and passes it to the caller
/// through the `body` closure.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
public protocol AsyncReader<ReadElement, ReadFailure>: ~Copyable, ~Escapable {
  /// The type of elements this reader reads.
  associatedtype ReadElement: ~Copyable

  /// The container type the reader uses to pass elements to the caller.
  associatedtype Buffer: RangeReplaceableContainer<ReadElement> & ~Copyable

  /// The error type that reading operations throw.
  associatedtype ReadFailure: Error

  /// Reads elements from the underlying source and passes them to the provided body closure.
  ///
  /// This method asynchronously reads elements from the source into a buffer,
  /// then passes the buffer to `body` for processing. When the buffer is empty,
  /// the stream has ended.
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// let result = try await fileReader.read { buffer in
  ///     guard buffer.count > 0 else {
  ///         return 0
  ///     }
  ///     return buffer.count
  /// }
  /// ```
  ///
  /// - Parameter body: A closure that receives a mutable reference to the buffer
  ///   of read elements and returns a value of type `Return`. When the buffer
  ///   is empty, it indicates the end of the stream.
  /// - Returns: The value the body closure returns after processing the read elements.
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
  ///   or a `Failure` from the body closure.
  mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout Buffer) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return
}
#endif

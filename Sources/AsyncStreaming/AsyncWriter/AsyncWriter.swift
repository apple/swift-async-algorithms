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

/// Writes elements asynchronously to a destination using callee-managed buffering.
///
/// Adopt ``AsyncWriter`` when you need callee-managed buffering,
/// where the writer supplies a buffer that the caller fills
/// with elements to write.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol AsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
  /// The type of elements this writer writes.
  associatedtype WriteElement: ~Copyable

  /// The container type the writer uses to receive elements from the caller.
  associatedtype Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable

  /// The error type that writing operations throw.
  associatedtype WriteFailure: Error

  /// Provides a buffer for writing elements to the destination.
  ///
  /// The writer supplies a buffer that `body` uses to append elements.
  /// The writer manages the buffer allocation and handles the writing
  /// operation once `body` completes.
  ///
  /// - Parameter body: A closure that receives a buffer for appending elements
  ///   to write. The closure returns a result of type `Return`.
  ///
  /// - Returns: The value the body closure returns.
  ///
  /// - Throws: An `EitherError` containing either a `WriteFailure` from the write operation
  ///   or a `Failure` from the body closure.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var writer: SomeAsyncWriter = ...
  ///
  /// try await writer.write { buffer in
  ///     for item in items {
  ///         buffer.append(item)
  ///     }
  ///     return buffer.count
  /// }
  /// ```
  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout Buffer) async throws(Failure) -> Return
  ) async throws(EitherError<WriteFailure, Failure>) -> Return
}
#endif

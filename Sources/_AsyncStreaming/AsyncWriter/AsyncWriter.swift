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
/// Writes elements asynchronously to a destination using a provided buffer.
///
/// Adopt ``AsyncWriter`` when you need to provide callee-managed buffering,
/// where the writer supplies an output span buffer that the caller fills
/// with elements to write.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol AsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
  /// The type of elements this writer writes.
  associatedtype WriteElement: ~Copyable

  /// The error type that writing operations throw.
  associatedtype WriteFailure: Error

  /// Provides a buffer for writing elements to the destination.
  ///
  /// The writer supplies an output span that `body` uses to append elements.
  /// The writer manages the buffer allocation and handles the writing
  /// operation once `body` completes.
  ///
  /// - Parameter body: A closure that receives an `OutputSpan` for appending elements
  ///   to write. The closure returns a result of type `Result`.
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
  /// try await writer.write { outputSpan in
  ///     for item in items {
  ///         outputSpan.append(item)
  ///     }
  ///     return outputSpan.count
  /// }
  /// ```
  mutating func write<Result, Failure: Error>(
    _ body: (inout OutputSpan<WriteElement>) async throws(Failure) -> Result
  ) async throws(EitherError<WriteFailure, Failure>) -> Result
}
#endif

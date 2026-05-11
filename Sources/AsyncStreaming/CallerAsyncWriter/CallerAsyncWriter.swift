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

/// Writes elements asynchronously from a caller-provided span.
///
/// Adopt ``CallerAsyncWriter`` when you need caller-managed buffering,
/// where the caller provides a span of elements for the writer
/// to consume.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, visionOS 1.0, *)
public protocol CallerAsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
  /// The type of elements this writer writes.
  associatedtype WriteElement: ~Copyable

  /// The error type that writing operations throw.
  associatedtype WriteFailure: Error

  /// Writes a span of elements to the underlying destination.
  ///
  /// This method asynchronously writes all elements from the provided span to whatever destination
  /// the writer represents. The operation may require multiple write calls to complete if the
  /// writer cannot accept all elements at once.
  ///
  /// - Parameter span: The span of elements to write. If not all elements can be written, `span` will be non-empty after `write` returns
  ///
  /// - Throws: A `WriteFailure` from the underlying write operation
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileWriter: FileAsyncWriter = ...
  /// let dataBuffer: [UInt8] = [1, 2, 3, 4, 5]
  ///
  /// // Write the entire span to a file asynchronously
  /// try await fileWriter.write(dataBuffer.span)
  /// ```
  mutating func write(
    span: borrowing InputSpan<WriteElement>
  ) async throws(WriteFailure)
}
#endif

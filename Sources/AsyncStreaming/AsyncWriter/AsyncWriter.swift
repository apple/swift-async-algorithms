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
///
/// ## Signaling end of stream
///
/// The writer is terminated by a call to ``finish(finalElement:)``.
/// Bulk transfer happens through ``write(_:)`` calls; ``finish(finalElement:)``
/// only carries the ``FinalElement`` payload.
///
/// The ``FinalElement`` associated type controls what data, if any, the writer
/// transmits alongside the end signal. The default is `Void`. Use a custom
/// type to carry data along with the end signal, or `Never` for endless
/// streams. When ``FinalElement`` is `Never`, ``finish(finalElement:)`` cannot
/// be called and the writer can be written to indefinitely.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
public protocol AsyncWriter<WriteElement, WriteFailure, FinalElement>: ~Copyable, ~Escapable {
  /// The type of elements this writer writes.
  // TODO: Check if we should support ~Escapable elements
  associatedtype WriteElement: ~Copyable

  /// The container type the writer uses to receive elements from the caller.
  // TODO: Check if we should support ~Escapable buffer
  associatedtype Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable

  /// The error type that writing operations throw.
  associatedtype WriteFailure: Error

  /// The data the writer delivers alongside the end-of-stream signal.
  ///
  /// Defaults to `Void`. Use a custom type to carry data along with the end
  /// signal.
  // TODO: Check if we should support ~Escapable final element
  associatedtype FinalElement: ~Copyable = Void

  /// Provides a buffer for writing elements to the destination.
  ///
  /// The writer supplies a buffer, sized by the implementation, that
  /// `body` uses to append elements. The writer manages the buffer
  /// allocation and handles the writing operation once `body` completes.
  /// Oversized payloads are split across multiple calls.
  ///
  /// - Parameter body: A closure that receives a buffer for appending elements
  ///   to write. The closure returns a result of type `Return`.
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
  ///
  /// - Returns: The value the body closure returns.
  ///
  /// - Throws: An `EitherError` containing either a `WriteFailure` from the write operation
  ///   or a `Failure` from the body closure.
  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout Buffer) async throws(Failure) -> Return
  ) async throws(EitherError<WriteFailure, Failure>) -> Return

  /// Closes the writer, delivering a ``FinalElement`` payload alongside the
  /// end-of-stream signal.
  ///
  /// - Parameter finalElement: The ``FinalElement`` payload to deliver with
  ///   the end signal.
  /// - Throws: A ``WriteFailure`` from the underlying write operation.
  consuming func finish(
    finalElement: consuming FinalElement
  ) async throws(WriteFailure)
}

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
extension AsyncWriter where Self: ~Copyable, Self: ~Escapable, FinalElement == Void {
  /// Concludes the writer with no payload.
  ///
  /// Available only when ``FinalElement`` is `Void`. Equivalent to calling
  /// ``finish(finalElement:)`` with `()`.
  public consuming func finish() async throws(WriteFailure) {
    try await self.finish(finalElement: ())
  }
}
#endif

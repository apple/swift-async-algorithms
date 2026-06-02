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
import BasicContainers

/// Writes elements asynchronously from a caller-provided buffer.
///
/// Adopt ``CallerAsyncWriter`` when you need caller-managed buffering,
/// where the caller provides a buffer of elements for the writer
/// to consume.
///
/// ## Signaling end of stream
///
/// The writer is terminated by a call to ``finish(buffer:finalElement:)``.
/// The `finish` call communicates a final buffer (if any) and the
/// ``FinalElement`` payload, allowing implementations to fuse the last data
/// frame with the end signal on transports that support it.
///
/// The ``FinalElement`` associated type controls what data, if any, the writer
/// transmits alongside the end signal. The default is `Void`. Use a custom
/// type to carry data along with the end signal, or `Never` for endless
/// streams. When ``FinalElement`` is `Never`, ``finish(buffer:finalElement:)``
/// cannot be called and the writer can be written to indefinitely.
///
/// Conformers must accept zero, one, or many `write(buffer:)` calls, optionally
/// followed by a single `finish(buffer:finalElement:)` call. After `finish`
/// returns, the writer is consumed and no further calls are valid.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
public protocol CallerAsyncWriter<WriteElement, WriteFailure, FinalElement>: ~Copyable, ~Escapable {
  /// The type of elements this writer writes.
  // TODO: Check if we should support ~Escapable elements
  associatedtype WriteElement: ~Copyable

  /// The error type that writing operations throw.
  associatedtype WriteFailure: Error

  /// The data the writer delivers alongside the end-of-stream signal.
  ///
  /// Defaults to `Void`.
  // TODO: Check if we should support ~Escapable final element
  associatedtype FinalElement: ~Copyable = Void

  /// Writes elements from the provided buffer to the underlying destination.
  ///
  /// This method asynchronously writes all elements from the provided buffer
  /// to the underlying destination.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileWriter: FileAsyncWriter = ...
  /// var data = UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
  ///
  /// try await fileWriter.write(buffer: &data)
  /// ```
  ///
  /// - Parameter buffer: The buffer of elements to write.
  ///
  /// - Throws: A `WriteFailure` from the underlying write operation.
  mutating func write<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer
  ) async throws(WriteFailure) where Buffer.Element: ~Copyable

  /// Sends the final buffer and ``FinalElement`` payload, and signals
  /// end-of-stream to the destination.
  ///
  /// The buffer may be empty if there is no remaining content to emit
  /// alongside the terminator. When ``FinalElement`` is `Void`, use the
  /// closure-less ``finish()`` convenience instead of passing `()` explicitly.
  ///
  /// - Parameters:
  ///   - buffer: The buffer of remaining elements to write alongside the
  ///     terminator.
  ///   - finalElement: The ``FinalElement`` payload to deliver with the end
  ///     signal.
  /// - Throws: A `WriteFailure` from the underlying write operation.
  consuming func finish<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) where Buffer.Element: ~Copyable
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension CallerAsyncWriter where Self: ~Copyable, Self: ~Escapable, FinalElement == Void {
  /// Concludes the writer with no final buffer and no extra payload.
  ///
  /// Available only when ``FinalElement`` is `Void`. Equivalent to calling
  /// ``finish(buffer:finalElement:)`` with an empty buffer and `()`.
  public consuming func finish() async throws(WriteFailure) {
    var empty = UniqueArray<WriteElement>()
    try await self.finish(buffer: &empty, finalElement: ())
  }
}
#endif

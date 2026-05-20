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

/// Reads elements asynchronously into a caller-provided buffer.
///
/// Adopt ``CallerAsyncReader`` when you need caller-managed buffering,
/// where the caller supplies a buffer that the reader fills
/// with elements.
///
/// ## Signaling end of stream
///
/// The reader signals end-of-stream by returning a non-`nil` ``FinalElement``
/// from ``read(into:)``. The same call may also append a final batch of
/// elements to the caller's buffer, allowing the reader to fuse the last
/// chunk with the end signal.
///
/// The ``FinalElement`` associated type controls what data, if any, the reader
/// delivers alongside the end signal. The default is `Void`. Use a custom type
/// to carry data along with the end signal, or `Never` for streams that never
/// end.
///
/// After the reader has returned a non-`nil` `FinalElement`, calling
/// ``read(into:)`` again is a programmer error.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
public protocol CallerAsyncReader<ReadElement, ReadFailure, FinalElement>: ~Copyable, ~Escapable {
  /// The type of elements this reader reads.
  // TODO: Check if we should support ~Escapable elements
  associatedtype ReadElement: ~Copyable

  /// The error type that reading operations throw.
  associatedtype ReadFailure: Error

  /// The data the reader delivers alongside the end-of-stream signal.
  ///
  /// Defaults to `Void`. Use a custom type to carry data along with the end
  /// signal, or `Never` for streams that never end.
  // TODO: Check if we should support ~Escapable final element
  associatedtype FinalElement: ~Copyable = Void

  /// Reads elements from the source into the provided buffer.
  ///
  /// This method appends elements into `buffer`. A non-`nil` return value
  /// signals end-of-stream and delivers the final payload. The call may
  /// also append a final batch of elements before signaling end.
  ///
  /// After the reader has returned a non-`nil` `FinalElement`, calling
  /// ``read(into:)`` again is a programmer error.
  ///
  /// - Parameter buffer: The buffer to fill with read elements.
  /// - Returns: A non-`nil` ``FinalElement`` if this call delivered the
  ///   end-of-stream signal; `nil` if more elements may follow.
  /// - Throws: A `ReadFailure` from the underlying read operation.
  // TODO: Check if we should support ~Escapable buffer
  mutating func read<Buffer: RangeReplaceableContainer<ReadElement> & ~Copyable>(
    into buffer: inout Buffer
  ) async throws(ReadFailure) -> FinalElement? where Buffer.Element: ~Copyable
}
#endif

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
///
/// ## Signaling end of stream
///
/// The reader signals end-of-stream by passing a non-`nil` value for the
/// `finalElement` parameter of the `body` closure. This call may also carry a
/// final chunk of elements in the buffer, allowing the reader to fuse the last
/// chunk with the end signal in a single operation.
///
/// The ``FinalElement`` associated type controls what data, if any, the reader
/// delivers alongside the end signal. The default is `Void`, which means the
/// signal carries no payload. Set ``FinalElement`` to a custom type when the
/// reader needs to deliver structured data with the terminator. Set it to `Never` to indicate
/// that the stream never ends — the `finalElement` parameter will always be `nil`.
///
/// After the reader has emitted a non-`nil` `finalElement`, calling
/// ``read(body:)`` again is a programmer error.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
public protocol AsyncReader<ReadElement, ReadFailure, FinalElement>: ~Copyable, ~Escapable {
  /// The type of elements this reader reads.
  // TODO: Check if we should support ~Escapable elements
  associatedtype ReadElement: ~Copyable

  /// The container type the reader uses to pass elements to the caller.
  // TODO: Check if we should support ~Escapable buffer
  associatedtype Buffer: RangeReplaceableContainer<ReadElement> & ~Copyable

  /// The error type that reading operations throw.
  associatedtype ReadFailure: Error

  /// The data the reader delivers alongside the end-of-stream signal.
  ///
  /// Defaults to `Void`. Use a custom type to carry data along with the
  /// end signal. Use `Never` for streams that never end.
  // TODO: Check if we should support ~Escapable final elements
  associatedtype FinalElement: ~Copyable = Void

  /// Reads elements from the underlying source and passes them to the provided body closure.
  ///
  /// This method asynchronously reads elements from the source into a buffer,
  /// then passes the buffer and an optional `finalElement` to `body` for
  /// processing.
  ///
  /// A `nil` value for `finalElement` means more data may follow. A non-`nil`
  /// value (which is the only way a stream of `FinalElement == Void` signals
  /// end) marks this chunk as the last one and delivers the final payload.
  /// The terminal chunk's buffer may be empty or contain a final batch of
  /// elements; the caller must process both.
  ///
  /// After the reader has emitted a non-`nil` `finalElement`, calling
  /// ``read(body:)`` again is a programmer error.
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// let result = try await fileReader.read { buffer, finalElement in
  ///     let processed = buffer.count
  ///     return (processed, finalElement != nil)
  /// }
  /// ```
  ///
  /// - Parameter body: A closure that receives a mutable reference to the buffer
  ///   of read elements together with the optional end-of-stream payload and
  ///   returns a value of type `Return`.
  /// - Returns: The value the body closure returns after processing the read elements.
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
  ///   or a `Failure` from the body closure.
  mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout Buffer, consuming FinalElement?) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return
}
#endif

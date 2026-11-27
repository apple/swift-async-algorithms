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

public import SpanPreview

public import ContainersPreview

/// Writes elements asynchronously from a buffer that the caller owns.
///
/// The caller either lends the elements as a `Span`, which the writer copies or
/// writes before it returns, or hands them over as an `InputSpan`, from which the
/// writer takes ownership. The latter lets a writer keep a buffer leased from a
/// pool until the destination is done with it.
///
/// ``finish(_:finalElement:)`` ends the stream and can fuse the last elements
/// with the end signal. With `FinalElement == Never`, `finish` cannot be called
/// and the stream never ends. Conformers accept zero or more writes, optionally
/// followed by a single `finish`.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
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

  /// Writes the given elements to the destination.
  ///
  /// ```swift
  /// let data: [UInt8] = [1, 2, 3, 4, 5]
  /// try await fileWriter.write(data.span)
  /// ```
  ///
  /// - Parameter elements: The elements to write. The writer has written or
  ///   copied all of them when the call returns.
  /// - Throws: A `WriteFailure` from the underlying write operation.
  mutating func write(
    _ elements: Span<WriteElement>
  ) async throws(WriteFailure)

  /// Writes the given elements to the destination and takes ownership of them.
  ///
  /// The default implementation writes `elements.span` and then destroys the
  /// elements.
  ///
  /// - Parameter elements: The elements to write. On return the span is empty.
  ///   If the call throws, the span keeps the elements that the writer did not take.
  /// - Throws: A `WriteFailure` from the underlying write operation.
  mutating func write(
    _ elements: inout InputSpan<WriteElement>
  ) async throws(WriteFailure)

  /// Writes the last elements, delivers the ``FinalElement`` payload, and
  /// signals end-of-stream.
  ///
  /// - Parameters:
  ///   - elements: The last elements to write. Can be empty.
  ///   - finalElement: The payload to deliver with the end signal.
  /// - Throws: A `WriteFailure` from the underlying write operation.
  consuming func finish(
    _ elements: Span<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure)

  /// Writes the last elements, takes ownership of them, delivers the
  /// ``FinalElement`` payload, and signals end-of-stream.
  ///
  /// The default implementation calls ``finish(_:finalElement:)`` with
  /// `elements.span` and then destroys the elements.
  ///
  /// - Parameters:
  ///   - elements: The last elements to write. Can be empty.
  ///   - finalElement: The payload to deliver with the end signal.
  /// - Throws: A `WriteFailure` from the underlying write operation.
  consuming func finish(
    _ elements: inout InputSpan<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure)
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension CallerAsyncWriter
where Self: ~Copyable, Self: ~Escapable, WriteElement: ~Copyable, FinalElement: ~Copyable {
  @inlinable
  public mutating func write(
    _ elements: inout InputSpan<WriteElement>
  ) async throws(WriteFailure) {
    try await self.write(elements.span)
    // `removeAll()` traps on an empty span that has no memory.
    if !elements.isEmpty {
      elements.removeAll()
    }
  }

  @inlinable
  public consuming func finish(
    _ elements: inout InputSpan<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) {
    try await self.finish(elements.span, finalElement: finalElement)
    // `removeAll()` traps on an empty span that has no memory.
    if !elements.isEmpty {
      elements.removeAll()
    }
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension CallerAsyncWriter where Self: ~Copyable, Self: ~Escapable, WriteElement: ~Copyable, FinalElement == Void {
  /// Ends the stream with no last elements and no payload.
  public consuming func finish() async throws(WriteFailure) {
    try await self.finish(Span<WriteElement>(), finalElement: ())
  }
}
#endif

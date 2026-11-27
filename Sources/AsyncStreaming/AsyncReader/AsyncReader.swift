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

/// Reads elements asynchronously from a source that owns the buffer.
///
/// The reader drains its source: each read lends the next elements to a
/// closure as an `InputSpan`. The closure can borrow them or remove them to take
/// ownership, for example of buffers leased from a pool. The reader destroys the
/// elements that the closure leaves in the span.
///
/// The reader signals end-of-stream with a non-`nil` ``FinalElement``, which can
/// come together with the last elements. With `FinalElement == Never`, the
/// stream never ends.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
public protocol AsyncReader<ReadElement, ReadFailure, FinalElement>: ~Copyable, ~Escapable {
  /// The type of elements this reader reads.
  // TODO: Check if we should support ~Escapable elements
  associatedtype ReadElement: ~Copyable

  /// The error type that reading operations throw.
  associatedtype ReadFailure: Error

  /// The data the reader delivers alongside the end-of-stream signal.
  ///
  /// Defaults to `Void`. Use `Never` for streams that never end.
  // TODO: Check if we should support ~Escapable final elements
  associatedtype FinalElement: ~Copyable = Void

  /// Reads the next elements of the source and lends them to `body`.
  ///
  /// The reader suspends until it can deliver at least one element or the end
  /// of the stream. Calling this method after the reader delivered a non-`nil`
  /// `finalElement` is a programmer error.
  ///
  /// ```swift
  /// let isFinished = try await reader.read(maxCount: 4096) { elements, finalElement in
  ///     process(elements.span)
  ///     return finalElement != nil
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - maxCount: The maximum number of elements that `body` receives. Must be
  ///     greater than zero.
  ///   - body: Receives the elements and, on the last read, the end-of-stream
  ///     payload. The reader destroys the elements that `body` leaves in the span.
  /// - Returns: The value that `body` returns.
  /// - Throws: A `ReadFailure` from the read, or the error of `body`.
  mutating func read<Return: ~Copyable, Failure: Error>(
    maxCount: Int,
    body: (inout InputSpan<ReadElement>, consuming FinalElement?) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
  /// Reads the next elements of the source, with no limit on their count, and
  /// lends them to `body`.
  @inlinable
  public mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout InputSpan<ReadElement>, consuming FinalElement?) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return {
    try await self.read(maxCount: Int.max, body: body)
  }
}
#endif

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

import ContainersPreview

// swift-format-ignore: AmbiguousTrailingClosureOverload
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
  /// Calls `body` for each chunk of the stream that is not empty, until the
  /// reader signals end-of-stream.
  ///
  /// ```swift
  /// _ = try await fileReader.forEachSpan { elements in
  ///     print("Processing \(elements.count) elements")
  /// }
  /// ```
  ///
  /// - Parameter body: Processes one chunk. The reader destroys the elements
  ///   that `body` leaves in the span.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal
  ///   chunk, or `nil` if none was observed.
  /// - Throws: A `ReadFailure` from the read, or the error of `body`.
  public consuming func forEachSpan<Failure: Error>(
    body: (inout InputSpan<ReadElement>) async throws(Failure) -> Void
  ) async throws(EitherError<ReadFailure, Failure>) -> FinalElement? {
    var final: FinalElement? = nil
    var done = false
    while !done {
      try await self.read { (next, finalElement) throws(Failure) -> Void in
        if !next.isEmpty {
          try await body(&next)
        }
        if finalElement != nil {
          final = finalElement
          done = true
        }
      }
    }
    return final
  }

  /// Calls `body` for each chunk of a stream that cannot fail, until the reader
  /// signals end-of-stream.
  ///
  /// - Parameter body: Processes one chunk. The reader destroys the elements
  ///   that `body` leaves in the span.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  @inlinable
  public consuming func forEachSpan(
    body: (inout InputSpan<ReadElement>) async -> Void
  ) async -> FinalElement where ReadFailure == Never {
    do {
      var final: FinalElement? = try await self.forEachSpan { (elements) async throws(Never) -> Void in
        await body(&elements)
      }
      // The force-unwrap is safe since final element must be set at this point
      return final.take()!
    } catch {
      fatalError()
    }
  }
}
#endif

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

import ContainersPreview

// swift-format-ignore: AmbiguousTrailingClosureOverload
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable {
  /// Iterates over all chunks from the reader, executing the provided body for
  /// each buffer until the stream signals end-of-stream.
  ///
  /// This method continuously reads chunks from the async reader, executing
  /// `body` for every chunk — including the terminal one — and terminates the
  /// loop when the reader delivers a non-`nil` ``AsyncReader/FinalElement``.
  /// The returned value is that ``AsyncReader/FinalElement``.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// _ = try await fileReader.forEachBuffer { buffer in
  ///     print("Processing \(buffer.count) elements")
  /// }
  /// ```
  ///
  /// - Parameter body: An asynchronous closure that processes each buffer of
  ///   elements read from the stream.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal
  ///   chunk, or `nil` if none was observed.
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the
  ///   read operation or a `Failure` from the body closure.
  public consuming func forEachBuffer<Failure: Error>(
    body: (inout Buffer) async throws(Failure) -> Void
  ) async throws(EitherError<ReadFailure, Failure>) -> FinalElement? {
    var final: FinalElement? = nil
    var done = false
    while !done {
      try await self.read { (next, finalElement) throws(Failure) -> Void in
        try await body(&next)
        if let finalElement {
          final = finalElement
          done = true
        }
      }
    }
    return final
  }

  /// Iterates over all chunks from a non-failing reader, executing the
  /// provided body for each buffer until the stream signals end-of-stream.
  ///
  /// Use this overload when the reader's ``AsyncReader/ReadFailure`` type is `Never`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// _ = await fileReader.forEachBuffer { buffer in
  ///     print("Processing \(buffer.count) elements")
  /// }
  /// ```
  ///
  /// - Parameter body: An asynchronous closure that processes each buffer of
  ///   elements read from the stream.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  @inlinable
  public consuming func forEachBuffer(
    body: (inout Buffer) async -> Void
  ) async -> FinalElement where ReadFailure == Never {
    var finalElement: FinalElement? = nil
    while finalElement == nil {
      do {
        try await self.read { (next, final) -> Void in
          await body(&next)
          if let final {
            finalElement = final
          }
        }
      } catch {
        fatalError()
      }
    }
    // The force-unwrap is safe since final element must be set at this point
    return finalElement!
  }
}
#endif

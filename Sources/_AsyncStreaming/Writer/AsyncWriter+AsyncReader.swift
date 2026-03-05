//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncWriter where Self: ~Copyable, Self: ~Escapable {
  /// Writes all elements from an async reader to this writer.
  ///
  /// This method consumes an async reader and writes all its elements to the underlying
  /// writer destination. It continuously reads spans of elements from the reader and writes
  /// them until the reader stream ends.
  ///
  /// - Parameter reader: An ``AsyncReader`` providing elements to write. The reader is
  ///   consumed by this operation.
  ///
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the reader or a nested
  ///   `EitherError<WriteFailure, AsyncWriterWroteShortError>` from the write operation.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileWriter: FileAsyncWriter = ...
  /// let dataReader: DataAsyncReader = ...
  ///
  /// // Copy all data from reader to writer
  /// try await fileWriter.write(dataReader)
  /// ```
  ///
  /// ## Discussion
  ///
  /// This method provides a convenient way to pipe data from one async stream to another,
  /// automatically handling the iteration and transfer of elements. The operation continues
  /// until the reader signals completion by producing an empty span.
  @_lifetime(self: copy self)
  public mutating func write<ReadFailure: Error>(
    _ reader: consuming some (AsyncReader<WriteElement, ReadFailure> & ~Copyable & ~Escapable)
  ) async throws(EitherError<ReadFailure, EitherError<WriteFailure, AsyncWriterWroteShortError>>)
  where WriteElement: Copyable {
    try await reader.forEach { (span) throws(EitherError<WriteFailure, AsyncWriterWroteShortError>) -> Void in
      try await self.write(span)
    }
  }
}
#endif

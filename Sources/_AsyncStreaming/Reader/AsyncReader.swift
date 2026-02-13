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
/// A protocol that represents an asynchronous reader capable of reading elements from some source.
///
/// ``AsyncReader`` defines an interface for types that can asynchronously read elements
/// of a specified type from a source.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol AsyncReader<ReadElement, ReadFailure>: ~Copyable, ~Escapable {
  /// The type of elements that can be read by this reader.
  associatedtype ReadElement: ~Copyable

  /// The type of error that can be thrown during reading operations.
  associatedtype ReadFailure: Error

  /// Reads elements from the underlying source and processes them with the provided body closure.
  ///
  /// This method asynchronously reads a span of elements from whatever source the reader
  /// represents, then passes them to the provided body closure. The operation may complete immediately
  /// or may await resources or processing time.
  ///
  /// - Parameter maximumCount: The maximum count of items the caller is ready
  ///   to process, or nil if the caller is prepared to accept an arbitrarily
  ///   large span. If non-nil, the maximum must be greater than zero.
  ///
  /// - Parameter body: A closure that consumes a span of read elements and performs some operation
  ///   on them, returning a value of type `Return`. When the span is empty, it indicates
  ///   the end of the reading operation or stream.
  ///
  /// - Returns: The value returned by the body closure after processing the read elements.
  ///
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
  ///   or a `Failure` from the body closure.
  ///
  /// ```swift
  /// var fileReader: FileAsyncReader = ...
  ///
  /// // Read data from a file asynchronously and process it
  /// let result = try await fileReader.read { data in
  ///     guard data.count > 0 else {
  ///         // Handle end of stream/terminal value
  ///         return finalProcessedValue
  ///     }
  ///     // Process the data
  ///     return data
  /// }
  /// ```
  #if compiler(<6.3)
  @_lifetime(&self)
  #endif
  mutating func read<Return, Failure: Error>(
    maximumCount: Int?,
    body: (consuming Span<ReadElement>) async throws(Failure) -> Return
  ) async throws(EitherError<ReadFailure, Failure>) -> Return

}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable {
  /// Reads elements from the underlying source and processes them with the provided body closure.
  ///
  /// This is a convenience method for async readers that never fail, simplifying the error handling
  /// by directly throwing the body closure's error type instead of wrapping it in `EitherError`.
  ///
  /// - Parameter maximumCount: The maximum count of items the caller is ready to process,
  ///   or nil if the caller is prepared to accept an arbitrarily large span.
  ///
  /// - Parameter body: A closure that consumes a span of read elements and performs some operation
  ///   on them, returning a value of type `Return`.
  ///
  /// - Returns: The value returned by the body closure after processing the read elements.
  ///
  /// - Throws: An error of type `Failure` if the body closure throws.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var reader: some AsyncReader<Int, Never> = ... // Never-failing reader
  ///
  /// let result = try await reader.read(maximumCount: 100) { span in
  ///     // Process the span
  ///     return span.count
  /// }
  /// ```
  #if compiler(<6.3)
  @_lifetime(&self)
  #endif
  public mutating func read<Return, Failure: Error>(
    maximumCount: Int?,
    body: (consuming Span<ReadElement>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return where Self.ReadFailure == Never {
    do {
      return try await self.read(maximumCount: maximumCount) { (span) throws(Failure) -> Return in
        return try await body(span)
      }
    } catch {
      switch error {
      case .first:
        fatalError()
      case .second(let error):
        throw error
      }
    }
  }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncReader where ReadElement: Copyable {
  /// Reads elements from this reader into the provided output span.
  ///
  /// This method reads a span of elements from the underlying reader and appends them
  /// to the provided output span. This is a convenience method for readers with copyable
  /// elements that need to populate an existing output buffer. The method reads up to
  /// the free capacity available in the output span.
  ///
  /// - Parameter outputSpan: An `OutputSpan` to append read elements into.
  ///
  /// - Throws: An error of type `ReadFailure` if the read operation cannot be completed successfully.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var reader: some AsyncReader<Int, Never> = ...
  /// var buffer = [Int](repeating: 0, count: 100)
  ///
  /// await buffer.withOutputSpan { outputSpan in
  ///     await reader.read(into: &outputSpan)
  /// }
  /// ```
  public mutating func read(
    into outputSpan: inout OutputSpan<ReadElement>
  ) async throws(ReadFailure) {
    do {
      try await self.read(maximumCount: outputSpan.freeCapacity) { span in
        for i in span.indices {
          outputSpan.append(span[i])
        }
      }
    } catch {
      switch error {
      case .first(let error):
        throw error
      case .second:
        fatalError()
      }
    }
  }
}
#endif

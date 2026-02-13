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
/// A protocol that represents an asynchronous writer capable of providing a buffer to write into.
///
/// ``AsyncWriter`` defines an interface for types that can asynchronously write elements
/// to a destination by providing an output span buffer for efficient batch writing operations.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol AsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
  /// The type of elements that can be written by this writer.
  associatedtype WriteElement: ~Copyable

  /// The type of error that can be thrown during writing operations.
  associatedtype WriteFailure: Error

  /// Provides a buffer to write elements into.
  ///
  /// This method supplies an output span that the body closure can use to append elements
  /// for writing. The writer manages the buffer allocation and handles the actual writing
  /// operation once the body closure completes.
  ///
  /// - Parameter body: A closure that receives an `OutputSpan` for appending elements
  ///   to write. The closure can return a result of type `Result`.
  ///
  /// - Returns: The value returned by the body closure.
  ///
  /// - Throws: An `EitherError` containing either a `WriteFailure` from the write operation
  ///   or a `Failure` from the body closure.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var writer: SomeAsyncWriter = ...
  ///
  /// try await writer.write { outputSpan in
  ///     for item in items {
  ///         outputSpan.append(item)
  ///     }
  ///     return outputSpan.count
  /// }
  /// ```
  // TODO: EOF should be signaled by providing an empty output span?
  #if compiler(<6.3)
  @_lifetime(self: copy self)
  #endif
  mutating func write<Result, Failure: Error>(
    _ body: (inout OutputSpan<WriteElement>) async throws(Failure) -> Result
  ) async throws(EitherError<WriteFailure, Failure>) -> Result

  /// Writes a span of elements to the underlying destination.
  ///
  /// This method asynchronously writes all elements from the provided span to whatever destination
  /// the writer represents. The operation may require multiple write calls to complete if the
  /// writer cannot accept all elements at once.
  ///
  /// - Parameter span: The span of elements to write.
  ///
  /// - Throws: An `EitherError` containing either a `WriteFailure` from the write operation
  ///   or an `AsyncWriterWroteShortError` if the writer cannot accept any more data before
  ///   all elements are written.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileWriter: FileAsyncWriter = ...
  /// let dataBuffer: [UInt8] = [1, 2, 3, 4, 5]
  ///
  /// // Write the entire span to a file asynchronously
  /// try await fileWriter.write(dataBuffer.span)
  /// ```
  #if compiler(<6.3)
  @_lifetime(self: copy self)
  #endif
  mutating func write(
    _ span: Span<WriteElement>
  ) async throws(EitherError<WriteFailure, AsyncWriterWroteShortError>)
}

/// An error that indicates the writer was unable to accept all provided elements.
///
/// This error is thrown when an async writer signals that it cannot accept any more data
/// by providing an empty output span, but there are still elements remaining to be written.
public struct AsyncWriterWroteShortError: Error {
  // TODO: This is just here to workaround https://github.com/swiftlang/swift/pull/86843
  private let dummy: (any Sendable)? = nil
  public init() {}
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncWriter where Self: ~Copyable, Self: ~Escapable {
  /// Writes the provided element to the underlying destination.
  ///
  /// This method asynchronously writes the given element to whatever destination the writer
  /// represents. The operation may complete immediately or may await resources or processing time.
  ///
  /// - Parameter element: The element to write. This typically represents a single item or a collection
  ///   of items depending on the specific writer implementation.
  ///
  /// - Throws: An error of type `WriteFailure` if the write operation cannot be completed successfully.
  ///
  /// - Note: This method is marked as `mutating` because writing operations often change the internal
  ///   state of the writer.
  ///
  /// ```swift
  /// var fileWriter: FileAsyncWriter = ...
  ///
  /// // Write data to a file asynchronously
  /// try await fileWriter.write(dataChunk)
  /// ```
  #if compiler(<6.3)
  @_lifetime(self: copy self)
  #endif
  public mutating func write(_ element: consuming WriteElement) async throws(WriteFailure) {
    // Since the element is ~Copyable but we don't have call-once closures
    // we need to move it into an Optional and then take it out once. This
    // also makes the below force unwrap safe
    var opt = Optional(element)
    do {
      try await self.write { outputSpan in
        outputSpan.append(opt.take()!)
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

  #if compiler(<6.3)
  @_lifetime(self: copy self)
  #endif
  public mutating func write(
    _ span: Span<WriteElement>
  ) async throws(EitherError<WriteFailure, AsyncWriterWroteShortError>)
  where WriteElement: Copyable {
    var index = span.indices.startIndex
    while index < span.indices.endIndex {
      try await self.write { (outputSpan) throws(AsyncWriterWroteShortError) -> Void in
        guard outputSpan.capacity != 0 else {
          throw AsyncWriterWroteShortError()
        }
        while !outputSpan.isFull && index < span.indices.endIndex {
          outputSpan.append(span[index])
          index += 1
        }
      }
    }
  }
}
#endif

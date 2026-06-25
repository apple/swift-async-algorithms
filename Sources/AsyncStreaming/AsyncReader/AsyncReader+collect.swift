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

/// An error that indicates the reader produced more elements than the
/// destination container could accept.
public struct AsyncReaderLeftOverElementsError: Error, Hashable {
  public init() {}
}

/// An error that indicates the reader signaled end-of-stream before producing
/// enough elements to fill the destination container.
public struct AsyncReaderInsufficientElementsError: Error, Hashable {
  public init() {}
}

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable {
  /// Collects elements from the reader into the provided container, up to the
  /// container's available space.
  ///
  /// Reads chunks from the reader and moves them into `target` until the reader
  /// signals end-of-stream. The reader can deliver fewer elements than
  /// `target.freeCapacity`; the container needn't be full when the stream ends.
  /// If the reader produces more elements than `target` can accept, the method
  /// throws ``AsyncReaderLeftOverElementsError``.
  ///
  /// - Parameter target: The container that receives the collected elements.
  ///   The method preserves the container's existing contents and appends
  ///   collected elements to the end.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  /// - Throws: An `EitherError` wrapping either a ``AsyncReader/ReadFailure`` or
  ///   an ``AsyncReaderLeftOverElementsError`` if the reader produced more
  ///   elements than `target` could accept.
  public consuming func collect<Container: RangeReplaceableContainer<ReadElement> & ~Copyable & ~Escapable>(
    into target: inout Container
  ) async throws(EitherError<ReadFailure, AsyncReaderLeftOverElementsError>) -> FinalElement {
    var reader = self
    var finalElement: FinalElement? = nil
    while finalElement == nil {
      try await reader.read { (buffer, final) throws(AsyncReaderLeftOverElementsError) -> Void in
        if buffer.count > target.freeCapacity {
          throw AsyncReaderLeftOverElementsError()
        }
        target.append(moving: buffer.startIndex..<buffer.endIndex, from: &buffer)
        if let final {
          finalElement = final
        }
      }
    }
    // The force-unwrap is safe since final element must be set at this point
    return finalElement!
  }

  /// Collects elements from the reader into the provided container, requiring
  /// that the reader fill the container exactly.
  ///
  /// Reads chunks from the reader and moves them into `target` until either the
  /// reader signals end-of-stream or the container becomes full. The reader
  /// must produce exactly `target.freeCapacity` elements. If it produces fewer
  /// before signaling end-of-stream, the method throws
  /// ``AsyncReaderInsufficientElementsError``. If it produces more, it throws
  /// ``AsyncReaderLeftOverElementsError``.
  ///
  /// - Parameter target: The container to fill exactly. The method appends
  ///   collected elements to the container's existing contents.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  /// - Throws: An `EitherError` wrapping either a ``AsyncReader/ReadFailure``
  ///   or an `EitherError` wrapping
  ///   ``AsyncReaderLeftOverElementsError`` (too many elements) or
  ///   ``AsyncReaderInsufficientElementsError`` (too few elements).
  public consuming func collect<Container: RangeReplaceableContainer<ReadElement> & ~Copyable & ~Escapable>(
    exactlyInto target: inout Container
  ) async throws(EitherError<
    ReadFailure, EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>
  >) -> FinalElement {
    var reader = self
    var finalElement: FinalElement? = nil
    while finalElement == nil {
      try await reader.read {
        (
          buffer,
          final
        ) throws(EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>) -> Void in
        if buffer.count > target.freeCapacity {
          throw .first(AsyncReaderLeftOverElementsError())
        }
        if final != nil, buffer.count < target.freeCapacity {
          throw .second(AsyncReaderInsufficientElementsError())
        }
        target.append(moving: buffer.startIndex..<buffer.endIndex, from: &buffer)
        if let final {
          finalElement = final
        }
      }
    }
    // The force-unwrap is safe since final element must be set at this point
    return finalElement!
  }

  /// Collects elements from the reader into the provided dynamic container,
  /// growing it up to the specified maximum size.
  ///
  /// Reads chunks from the reader and appends them to `target`, which grows as
  /// elements arrive. The reader can deliver fewer than `maximumSize` elements
  /// before signaling end-of-stream; if it delivers more, the method throws
  /// ``AsyncReaderLeftOverElementsError``.
  ///
  /// - Parameters:
  ///   - target: The dynamic container that receives the collected elements.
  ///     The method appends collected elements to the container's existing
  ///     contents.
  ///   - maximumSize: The maximum number of elements to append to `target`.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  /// - Throws: An `EitherError` wrapping either a ``AsyncReader/ReadFailure`` or
  ///   an ``AsyncReaderLeftOverElementsError`` if the reader produced more than
  ///   `maximumSize` elements.
  public consuming func collect<Container: DynamicContainer<ReadElement> & ~Copyable>(
    into target: inout Container,
    maximumSize: Int
  ) async throws(EitherError<ReadFailure, AsyncReaderLeftOverElementsError>) -> FinalElement {
    precondition(maximumSize >= 0, "maximumSize must be non-negative")
    var reader = self
    var finalElement: FinalElement? = nil
    var remaining = maximumSize
    while finalElement == nil {
      try await reader.read { (buffer, final) throws(AsyncReaderLeftOverElementsError) -> Void in
        let chunkCount = buffer.count
        if chunkCount > remaining {
          throw AsyncReaderLeftOverElementsError()
        }
        if chunkCount > 0 {
          var consumer = buffer.consumeAll()
          while let element = consumer.next() {
            target.append(element)
          }
          remaining -= chunkCount
        }
        if let final {
          finalElement = final
        }
      }
    }
    // The force-unwrap is safe since final element must be set at this point
    return finalElement!
  }
}

#endif

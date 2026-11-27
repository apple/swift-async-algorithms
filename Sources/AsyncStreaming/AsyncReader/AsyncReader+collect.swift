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

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
  /// Moves the elements of the stream into `target`, up to its free capacity.
  ///
  /// The reader can deliver fewer elements than `target.freeCapacity`.
  ///
  /// - Parameter target: Receives the elements after its existing contents.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  /// - Throws: A ``AsyncReader/ReadFailure``, or ``AsyncReaderLeftOverElementsError``
  ///   if the reader produced more elements than `target` could accept.
  public consuming func collect(
    into target: inout OutputSpan<ReadElement>
  ) async throws(EitherError<ReadFailure, AsyncReaderLeftOverElementsError>) -> FinalElement {
    var reader = self
    var finalElement: FinalElement? = nil
    while finalElement == nil {
      try await reader.read { (elements, final) throws(AsyncReaderLeftOverElementsError) -> Void in
        if elements.count > target.freeCapacity {
          throw AsyncReaderLeftOverElementsError()
        }
        target.append(moving: &elements)
        finalElement = final
      }
    }
    // The force-unwrap is safe since final element must be set at this point
    return finalElement.take()!
  }

  /// Moves the elements of the stream into `target`, which the reader must fill
  /// exactly.
  ///
  /// - Parameter target: Receives the elements after its existing contents.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  /// - Throws: A ``AsyncReader/ReadFailure``, ``AsyncReaderLeftOverElementsError``
  ///   for too many elements, or ``AsyncReaderInsufficientElementsError`` for too few.
  public consuming func collect(
    exactlyInto target: inout OutputSpan<ReadElement>
  ) async throws(EitherError<
    ReadFailure, EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>
  >) -> FinalElement {
    var reader = self
    var finalElement: FinalElement? = nil
    while finalElement == nil {
      try await reader.read {
        (
          elements,
          final
        ) throws(EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>) -> Void in
        if elements.count > target.freeCapacity {
          throw .first(AsyncReaderLeftOverElementsError())
        }
        if final != nil, elements.count < target.freeCapacity {
          throw .second(AsyncReaderInsufficientElementsError())
        }
        target.append(moving: &elements)
        finalElement = final
      }
    }
    // The force-unwrap is safe since final element must be set at this point
    return finalElement.take()!
  }

  /// Moves the elements of the stream into `target`, which grows by at most
  /// `maximumSize` elements.
  ///
  /// - Parameters:
  ///   - target: Receives the elements after its existing contents.
  ///   - maximumSize: The maximum number of elements to append to `target`.
  /// - Returns: The ``AsyncReader/FinalElement`` delivered with the terminal chunk.
  /// - Throws: A ``AsyncReader/ReadFailure``, or ``AsyncReaderLeftOverElementsError``
  ///   if the reader produced more than `maximumSize` elements.
  public consuming func collect<Container: DynamicContainer<ReadElement> & ~Copyable>(
    into target: inout Container,
    maximumSize: Int
  ) async throws(EitherError<ReadFailure, AsyncReaderLeftOverElementsError>) -> FinalElement
  where Container.Element: ~Copyable {
    precondition(maximumSize >= 0, "maximumSize must be non-negative")
    var reader = self
    var finalElement: FinalElement? = nil
    var remaining = maximumSize
    while finalElement == nil {
      try await reader.read { (elements, final) throws(AsyncReaderLeftOverElementsError) -> Void in
        let chunkCount = elements.count
        if chunkCount > remaining {
          throw AsyncReaderLeftOverElementsError()
        }
        if chunkCount > 0 {
          target.append(addingCount: chunkCount) { output in
            output.append(moving: &elements)
          }
          remaining -= chunkCount
        }
        finalElement = final
      }
    }
    // The force-unwrap is safe since final element must be set at this point
    return finalElement.take()!
  }
}

#endif

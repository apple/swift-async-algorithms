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
import BasicContainers

/// An error indicating that the reader produced more elements than the specified collection limit.
///
/// This error occurs when calling ``AsyncReader/collect(upTo:body:)`` and the reader's buffer
/// contains more elements than the allowed limit.
public struct AsyncReaderLeftOverElementsError: Error, Hashable {
  public init() {}
}

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable {
  /// Collects elements from the reader up to a specified limit and processes them.
  ///
  /// This method continuously reads elements from the async reader, accumulating them in an
  /// internal buffer until either it reaches the end of the stream or the specified limit.
  /// Once collection completes, it passes the accumulated elements to the provided body
  /// closure as an `InputSpan` for processing.
  ///
  /// - Parameters:
  ///   - limit: The maximum number of elements to collect. This prevents unbounded memory
  ///     growth when reading from potentially infinite streams.
  ///   - body: A closure that receives an `InputSpan` containing all collected elements and returns
  ///     a result of type `Result`.
  ///
  /// - Returns: The value returned by the body closure after processing the collected elements.
  ///
  /// - Throws: An `EitherError` wrapping either a read failure (which itself may be an
  ///   ``AsyncReaderLeftOverElementsError`` if the reader produces more elements than the limit),
  ///   or a `Failure` from the body closure.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var reader: SomeAsyncReader = ...
  ///
  /// let processedData = try await reader.collect(upTo: 1000) { span in
  ///     // Process all collected elements
  /// }
  /// ```
  public mutating func collect<Result, Failure: Error>(
    upTo limit: Int,
    body: (consuming InputSpan<ReadElement>) async throws(Failure) -> Result
  ) async throws(EitherError<EitherError<ReadFailure, AsyncReaderLeftOverElementsError>, Failure>) -> Result {
    // TODO: In the future we might want to use a temporary allocation instead
    // but those don't support async closures yet.
    var collectedBuffer = UniqueArray<ReadElement>()
    collectedBuffer.reserveCapacity(limit)
    var shouldContinue = true
    do {
      while shouldContinue {
        try await self.read { (buffer: inout Buffer) throws(AsyncReaderLeftOverElementsError) -> Void in
          guard buffer.count > 0 else {
            shouldContinue = false
            return
          }
          if limit - collectedBuffer.count < buffer.count {
            throw AsyncReaderLeftOverElementsError()
          }
          var consumer = buffer.consumeAll()
          while let element = consumer.next() {
            collectedBuffer.append(element)
          }
        }
      }
    } catch {
      throw .first(error)
    }
    do {
      var consumer = collectedBuffer.consumeAll()
      return try await body(consumer.drainNext())
    } catch {
      throw .second(error)
    }
  }
}

#endif

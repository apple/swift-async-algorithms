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
  /// internal buffer until either the reader signals end-of-stream (by delivering a
  /// non-`nil` ``AsyncReader/FinalElement``) or the specified limit is reached.
  /// Once collection completes, it passes the accumulated elements to the provided body
  /// closure as an `InputSpan` for processing, and returns the body's result together
  /// with the ``AsyncReader/FinalElement``.
  ///
  /// - Parameters:
  ///   - limit: The maximum number of elements to collect. This prevents unbounded memory
  ///     growth when reading from potentially infinite streams.
  ///   - body: A closure that receives an `InputSpan` containing all collected elements and returns
  ///     a result of type `Result`.
  ///
  /// - Returns: A tuple of the body closure's result and the ``AsyncReader/FinalElement``
  ///   delivered with the terminal chunk.
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
  /// let (processedData, _) = try await reader.collect(upTo: 1000) { span in
  ///     // Process all collected elements
  /// }
  /// ```
  // TODO: We should make this method take an inout `RangeReplacableCollection` instead
  public consuming func collect<Result, Failure: Error>(
    upTo limit: Int,
    body: (consuming InputSpan<ReadElement>) async throws(Failure) -> Result
  ) async throws(EitherError<EitherError<ReadFailure, AsyncReaderLeftOverElementsError>, Failure>) -> (
    Result, FinalElement
  ) {
    var reader = self
    // TODO: In the future we might want to use a temporary allocation instead
    // but those don't support async closures yet.
    var collectedBuffer = UniqueArray<ReadElement>()
    collectedBuffer.reserveCapacity(limit)
    var finalElement: FinalElement? = nil
    do {
      while finalElement == nil {
        try await reader.read {
          (buffer: inout Buffer, final: FinalElement?) throws(AsyncReaderLeftOverElementsError) -> Void in
          if buffer.count > 0 {
            if limit - collectedBuffer.count < buffer.count {
              throw AsyncReaderLeftOverElementsError()
            }
            var consumer = buffer.consumeAll()
            while let element = consumer.next() {
              collectedBuffer.append(element)
            }
          }
          if let final {
            finalElement = final
          }
        }
      }
    } catch {
      throw .first(error)
    }
    do {
      var consumer = collectedBuffer.consumeAll()
      let result = try await body(consumer.drainNext())
      // The force-unwrap is safe since final element must be set at this point
      return (result, finalElement!)
    } catch {
      throw .second(error)
    }
  }
}

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement == Void {
  /// Collects elements from the reader up to a specified limit and processes them.
  ///
  /// This overload is available when ``AsyncReader/FinalElement`` is `Void`.
  /// It returns only the body closure's result — there is no payload to surface.
  ///
  /// - Parameters:
  ///   - limit: The maximum number of elements to collect.
  ///   - body: A closure that receives an `InputSpan` of collected elements.
  /// - Returns: The body closure's result.
  /// - Throws: An `EitherError` wrapping either a read failure (possibly an
  ///   ``AsyncReaderLeftOverElementsError``) or a `Failure` from `body`.
  // TODO: We should make this method take an inout `RangeReplacableCollection` instead
  public consuming func collect<Result, Failure: Error>(
    upTo limit: Int,
    body: (consuming InputSpan<ReadElement>) async throws(Failure) -> Result
  ) async throws(EitherError<EitherError<ReadFailure, AsyncReaderLeftOverElementsError>, Failure>) -> Result {
    let (result, _): (Result, Void?) = try await self.collect(upTo: limit, body: body)
    return result
  }
}

#endif

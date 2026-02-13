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
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: Copyable {
  /// Collects elements from the reader up to a specified limit and processes them with a body function.
  ///
  /// This method continuously reads elements from the async reader, accumulating them in a buffer
  /// until either the end of the stream is reached (indicated by a `nil` element) or the specified
  /// limit is exceeded. Once collection is complete, the accumulated elements are passed to the
  /// provided body function as a `Span` for processing.
  ///
  /// - Parameters:
  ///   - limit: The maximum number of elements to collect. This prevents unbounded memory
  ///     growth when reading from potentially infinite streams.
  ///   - body: A closure that receives a `Span` containing all collected elements and returns
  ///     a result of type `Result`. This closure is called once after all elements have been
  ///     collected successfully.
  ///
  /// - Returns: The value returned by the body closure after processing the collected elements.
  ///
  /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
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
  ///
  /// ## Memory Considerations
  ///
  /// Since this method buffers all elements in memory before processing, it should be used
  /// with caution on large datasets. The `limit` parameter serves as a safety mechanism
  /// to prevent excessive memory usage.
  #if compiler(<6.3)
  @_lifetime(&self)
  #endif
  public mutating func collect<Result, Failure: Error>(
    upTo limit: Int,
    body: (Span<ReadElement>) async throws(Failure) -> Result
  ) async throws(EitherError<ReadFailure, Failure>) -> Result {
    var buffer = [ReadElement]()
    var shouldContinue = true
    do {
      while shouldContinue {
        try await self.read(maximumCount: limit - buffer.count) { span in
          guard span.count > 0 else {
            shouldContinue = false
            return
          }
          precondition(span.count <= limit - buffer.count)
          for index in span.indices {
            buffer.append(span[index])
          }
        }
      }
    } catch {
      switch error {
      case .first(let error):
        throw .first(error)
      case .second:
        fatalError()
      }
    }
    do {
      return try await body(buffer.span)
    } catch {
      throw .second(error)
    }
  }

  /// Collects elements from the reader up to a specified limit and processes them with a body function.
  ///
  /// This method continuously reads elements from the async reader, accumulating them in a buffer
  /// until either the end of the stream is reached (indicated by a `nil` element) or the specified
  /// limit is exceeded. Once collection is complete, the accumulated elements are passed to the
  /// provided body function as a `Span` for processing.
  ///
  /// - Parameters:
  ///   - limit: The maximum number of elements to collect before throwing a `LimitExceeded` error.
  ///     This prevents unbounded memory growth when reading from potentially infinite streams.
  ///   - body: A closure that receives a `Span` containing all collected elements and returns
  ///     a result of type `Result`. This closure is called once after all elements have been
  ///     collected successfully.
  ///
  /// - Returns: The value returned by the body closure after processing the collected elements.
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
  ///
  /// ## Memory Considerations
  ///
  /// Since this method buffers all elements in memory before processing, it should be used
  /// with caution on large datasets. The `limit` parameter serves as a safety mechanism
  /// to prevent excessive memory usage.
  #if compiler(<6.3)
  @_lifetime(&self)
  #endif
  public mutating func collect<Result>(
    upTo limit: Int,
    body: (Span<ReadElement>) async -> Result
  ) async -> Result where ReadFailure == Never {
    var buffer = [ReadElement]()
    var shouldContinue = true
    while limit - buffer.count > 0 && shouldContinue {
      // This force-try is safe since neither read nor the closure are throwing
      try! await self.read(maximumCount: limit - buffer.count) { span in
        precondition(span.count <= limit - buffer.count)
        guard span.count > 0 else {
          // This means the underlying reader is finished and we can return
          shouldContinue = false
          return
        }
        for index in span.indices {
          buffer.append(span[index])
        }
      }
    }
    return await body(buffer.span)
  }

  /// Collects elements from the reader into an output span until the span is full.
  ///
  /// This method continuously reads elements from the async reader and appends them to the
  /// provided output span until the span reaches its capacity. This provides an efficient
  /// way to fill a pre-allocated buffer with elements from the reader.
  ///
  /// - Parameter outputSpan: An `OutputSpan` to append read elements into. The method continues
  ///   reading until this span is full.
  ///
  /// - Throws: An error of type `ReadFailure` if any read operation fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var reader: SomeAsyncReader = ...
  /// var buffer = [Int](repeating: 0, count: 100)
  ///
  /// try await buffer.withOutputSpan { outputSpan in
  ///     try await reader.collect(into: &outputSpan)
  /// }
  /// ```
  #if compiler(<6.3)
  @_lifetime(&self)
  #endif
  public mutating func collect(
    into outputSpan: inout OutputSpan<ReadElement>
  ) async throws(ReadFailure) {
    while !outputSpan.isFull {
      do {
        try await self.read(maximumCount: outputSpan.freeCapacity) { span in
          for index in span.indices {
            outputSpan.append(span[index])
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
}
#endif

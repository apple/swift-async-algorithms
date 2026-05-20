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
import BasicContainers

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension CallerAsyncReader where Self: ~Copyable, Self: ~Escapable, Self.ReadElement: ~Copyable {
  /// Pipes all elements from this reader into the given writer.
  ///
  /// This method consumes the reader and writes all of its elements into the writer's
  /// destination. It continuously reads chunks into buffers supplied by the writer and
  /// flushes them until this reader's stream ends.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataCallerAsyncReader = ...
  /// var fileWriter: FileAsyncWriter = ...
  ///
  /// // Copy all data from reader to writer
  /// try await dataReader.pipe(into: &fileWriter)
  /// ```
  ///
  /// - Parameter writer: An ``AsyncWriter`` to receive the elements. The writer is mutated
  ///   in place and remains usable after this operation.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    into writer: inout Writer
  ) async throws(EitherError<Writer.WriteFailure, ReadFailure>)
  where Writer: AsyncWriter & ~Copyable & ~Escapable, Writer.WriteElement == ReadElement {
    var shouldContinue = true
    while shouldContinue {
      try await writer
        .write { (buffer: inout Writer.Buffer) throws(ReadFailure) in
          try await self.read(into: &buffer)
          if buffer.count == 0 {
            shouldContinue = false
          }
        }
    }
  }

  /// Pipes all elements from this reader into the given writer through an intermediate buffer.
  ///
  /// This method consumes the reader and writes all of its elements into the writer's
  /// destination. Because neither the reader nor the writer supplies a buffer, this
  /// method allocates an intermediate buffer of the requested capacity and reuses it
  /// across iterations: each iteration fills the buffer from the reader and then hands
  /// it to the writer to drain.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataCallerAsyncReader = ...
  /// var fileWriter: FileCallerAsyncWriter = ...
  ///
  /// // Copy all data from reader to writer using a 4 KB intermediate buffer
  /// try await dataReader.pipe(bufferingInto: &fileWriter, intermediateCapacity: 4096)
  /// ```
  ///
  /// - Parameters:
  ///   - writer: A ``CallerAsyncWriter`` to receive the elements. The writer is mutated
  ///     in place and remains usable after this operation.
  ///   - intermediateCapacity: The capacity of the intermediate buffer that mediates
  ///     between the reader and writer. Larger values reduce the number of read and
  ///     write calls at the cost of memory.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    bufferingInto writer: inout Writer,
    intermediateCapacity: Int
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
  where Writer: CallerAsyncWriter & ~Copyable & ~Escapable, Writer.WriteElement == ReadElement {
    var buffer = UniqueArray<ReadElement>(minimumCapacity: intermediateCapacity)
    var shouldContinue = true
    while shouldContinue {
      do throws(ReadFailure) {
        try await self.read(into: &buffer)
      } catch {
        throw .first(error)
      }
      if buffer.count == 0 {
        shouldContinue = false
      } else {
        do throws(Writer.WriteFailure) {
          try await writer.write(buffer: &buffer)
          assert(buffer.count == 0, "CallerAsyncWriter must drain the buffer during write(buffer:)")
        } catch {
          throw .second(error)
        }
      }
    }
  }
}
#endif

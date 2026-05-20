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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, Self.ReadElement: ~Copyable {
  /// Pipes all elements from this reader into the given writer.
  ///
  /// This method consumes the reader and writes all of its elements into the writer's
  /// destination. It iterates over each buffer the reader produces and hands it to the
  /// writer until this reader's stream ends.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataAsyncReader = ...
  /// var fileWriter: FileCallerAsyncWriter = ...
  ///
  /// // Copy all data from reader to writer
  /// try await dataReader.pipe(into: &fileWriter)
  /// ```
  ///
  /// - Parameter writer: A ``CallerAsyncWriter`` to receive the elements. The writer is
  ///   mutated in place and remains usable after this operation.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    into writer: inout Writer
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
  where Writer: CallerAsyncWriter & ~Copyable & ~Escapable, Writer.WriteElement == ReadElement {
    try await self.forEachBuffer { (buffer: inout Buffer) throws(Writer.WriteFailure) in
      try await writer.write(buffer: &buffer)
    }
  }

  /// Pipes all elements from this reader into the given writer, copying each element from the reader's
  /// buffer into the writer's buffer.
  ///
  /// This method consumes the reader and writes all of its elements into the writer's
  /// destination. Because both protocols supply their own buffer, each element must be
  /// transferred from the reader's buffer into the writer's buffer. The writer's buffer
  /// may be smaller than the reader's, in which case multiple `write` calls are issued
  /// per chunk produced by the reader.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataAsyncReader = ...
  /// var fileWriter: FileAsyncWriter = ...
  ///
  /// // Copy all data from reader to writer
  /// try await dataReader.pipe(copyingInto: &fileWriter)
  /// ```
  ///
  /// - Parameter writer: An ``AsyncWriter`` to receive the elements. The writer is
  ///   mutated in place and remains usable after this operation.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    copyingInto writer: inout Writer
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
  where Writer: AsyncWriter & ~Copyable & ~Escapable, Writer.WriteElement == ReadElement {
    try await self.forEachBuffer { (readerBuffer: inout Buffer) throws(Writer.WriteFailure) in
      var consumer = readerBuffer.consumeAll()
      while let firstElement = consumer.next() {
        var pending: ReadElement? = firstElement
        do throws(EitherError<Writer.WriteFailure, Never>) {
          try await writer.write { (writerBuffer: inout Writer.Buffer) in
            switch consume pending {
            case .some(let element):
              writerBuffer.append(element)
            case .none:
              break
            }
            pending = nil
            // TODO: We should check if we can use one of the append methods instead of
            // element by element copies in the future
            while writerBuffer.freeCapacity > 0 {
              guard let element = consumer.next() else { return }
              writerBuffer.append(element)
            }
          }
        } catch {
          switch error {
          case .first(let writeFailure):
            throw writeFailure
          case .second:
            fatalError("Unreachable")
          }
        }
      }
    }
  }
}
#endif

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

// TODO: The `Writer` generic parameter on every `pipe` variant in this file
// should additionally be constrained `& ~Escapable`. We currently can't express
// that because of a Swift lifetime-checker limitation: with `FinalElement:
// ~Copyable`, the `consuming FinalElement?` parameter on the read closure
// changes the closure's lifetime category, and capturing a `~Escapable Writer`
// inside that closure (which `pipe` does, via the `writerOpt` Optional that
// alternates between `write` and `finish` calls) trips
// "lifetime-dependent variable 'writer' escapes its scope". When that
// restriction is relaxed (or `pipe` is restructured to avoid capturing the
// writer across the read closure boundary) the constraint should be added
// back so `pipe` works for `~Escapable` writers too.

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, Self.ReadElement: ~Copyable {
  /// Pipes all elements from this reader into the given writer, fusing the
  /// terminal chunk with a `finish` on the writer.
  ///
  /// Consumes both the reader and the writer. Each chunk the reader produces is
  /// forwarded with `writer.write(buffer:)` until the reader signals
  /// end-of-stream by delivering a non-`nil` ``AsyncReader/FinalElement``. The
  /// terminal chunk is fused with the writer's ``CallerAsyncWriter/finish(buffer:finalElement:)``.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataAsyncReader = ...
  /// let fileWriter: FileCallerAsyncWriter = ...
  ///
  /// // Copy all data from reader to writer and finish the writer.
  /// try await dataReader.pipe(into: fileWriter)
  /// ```
  ///
  /// - Parameter writer: A ``CallerAsyncWriter`` to receive the elements. The
  ///   writer is consumed; its ``CallerAsyncWriter/finish(buffer:finalElement:)``
  ///   method is called with the reader's terminal chunk and ``AsyncReader/FinalElement``.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    into writer: consuming Writer
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
  where
    Writer: CallerAsyncWriter & ~Copyable,
    Writer.WriteElement == ReadElement,
    Writer.FinalElement == FinalElement
  {
    var reader = self
    var writerOpt: Writer? = .some(writer)
    var done = false
    while !done {
      try await reader.read { (buffer: inout Buffer, finalElement: FinalElement?) throws(Writer.WriteFailure) -> Void in
        if let finalElement {
          let w = writerOpt.take()!
          try await w.finish(buffer: &buffer, finalElement: finalElement)
          done = true
        } else {
          try await writerOpt!.write(buffer: &buffer)
        }
      }
    }
  }

  /// Pipes all elements from this reader into the given writer, copying each
  /// element from the reader's buffer into the writer's buffer.
  ///
  /// Consumes both the reader and the writer. Because both protocols supply
  /// their own buffer, each element is transferred between them. The writer's
  /// buffer may be smaller than the reader's, in which case multiple `write`
  /// calls are issued per chunk produced by the reader.
  ///
  /// On the terminal chunk this method drains all bytes through `write` calls
  /// first and then calls ``AsyncWriter/finish(finalElement:)`` carrying
  /// only the ``AsyncReader/FinalElement`` payload.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataAsyncReader = ...
  /// let fileWriter: FileAsyncWriter = ...
  ///
  /// try await dataReader.pipe(copyingInto: fileWriter)
  /// ```
  ///
  /// - Parameter writer: An ``AsyncWriter`` to receive the elements. The
  ///   writer is consumed; its ``AsyncWriter/finish(finalElement:)`` method
  ///   is called with the reader's ``AsyncReader/FinalElement`` payload.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    copyingInto writer: consuming Writer
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
  where
    Writer: AsyncWriter & ~Copyable,
    Writer.WriteElement == ReadElement,
    Writer.FinalElement == FinalElement
  {
    var reader = self
    var writerOpt: Writer? = .some(writer)
    var done = false
    while !done {
      try await reader.read {
        (readerBuffer: inout Buffer, finalElement: FinalElement?) throws(Writer.WriteFailure) -> Void in
        try await Self.drain(readerBuffer: &readerBuffer, into: &writerOpt!)
        if let finalElement {
          let w = writerOpt.take()!
          try await w.finish(finalElement: finalElement)
          done = true
        }
      }
    }
  }

  /// Drains `readerBuffer` into `writer` across as many `write` calls as
  /// required to move every element. Used by ``pipe(copyingInto:)`` to share
  /// the multi-write loop between mid-stream and terminal chunks.
  private static func drain<Writer>(
    readerBuffer: inout Buffer,
    into writer: inout Writer
  ) async throws(Writer.WriteFailure)
  where
    Writer: AsyncWriter & ~Copyable,
    Writer.WriteElement == ReadElement
  {
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
          while writerBuffer.freeCapacity > 0 {
            guard let element = consumer.next() else { return }
            writerBuffer.append(element)
          }
        }
      } catch {
        switch error {
        case .first(let writeFailure): throw writeFailure
        case .second: fatalError("Unreachable")
        }
      }
    }
  }
}
#endif

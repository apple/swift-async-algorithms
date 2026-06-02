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

// TODO: The `Writer` generic parameter on every `pipe` variant in this file
// should additionally be constrained `& ~Escapable`. We currently can't
// express that because of a Swift lifetime-checker limitation: with
// `FinalElement: ~Copyable`, the `consuming FinalElement?` parameter on the
// reader's `read` closure changes the closure's lifetime category, and
// capturing a `~Escapable Writer` inside that closure (which `pipe` does, via
// the `writerOpt` Optional that alternates between `write` and `finish`
// calls) trips "lifetime-dependent variable 'writer' escapes its scope".
// When that restriction is relaxed (or `pipe` is restructured to avoid
// capturing the writer across the closure boundary) the constraint should be
// added back so `pipe` works for `~Escapable` writers too.

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
extension CallerAsyncReader where Self: ~Copyable, Self: ~Escapable, Self.ReadElement: ~Copyable {
  /// Pipes all elements from this reader into the given writer, then signals
  /// end-of-stream with a `finish` call on the writer.
  ///
  /// Consumes both the reader and the writer. The reader fills the writer's
  /// buffer on each iteration; once the reader signals end-of-stream, the
  /// writer's ``AsyncWriter/finish(finalElement:)`` is called with the reader's
  /// ``CallerAsyncReader/FinalElement``.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataCallerAsyncReader = ...
  /// let fileWriter: FileAsyncWriter = ...
  ///
  /// try await dataReader.pipe(into: fileWriter)
  /// ```
  ///
  /// - Parameter writer: An ``AsyncWriter`` to receive the elements. The
  ///   writer is consumed.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    into writer: consuming Writer
  ) async throws(EitherError<Writer.WriteFailure, ReadFailure>)
  where
    Writer: AsyncWriter & ~Copyable,
    Writer.WriteElement == ReadElement,
    Writer.FinalElement == FinalElement
  {
    var reader = self
    var writerOpt: Writer? = .some(writer)
    var done = false
    while !done {
      var pendingFinal: FinalElement? = nil
      try await writerOpt!
        .write { (buffer: inout Writer.Buffer) throws(ReadFailure) -> Void in
          pendingFinal = try await reader.read(into: &buffer)
        }
      if let final = pendingFinal {
        let w = writerOpt.take()!
        do throws(Writer.WriteFailure) {
          try await w.finish(finalElement: final)
        } catch {
          throw .first(error)
        }
        done = true
      }
    }
  }

  /// Pipes all elements from this reader into the given writer through an intermediate buffer.
  ///
  /// Consumes both the reader and the writer. Because neither protocol supplies
  /// a buffer, this method allocates an intermediate buffer of the requested
  /// capacity and reuses it across iterations. The terminal chunk is fused
  /// with the writer's ``CallerAsyncWriter/finish(buffer:finalElement:)``.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let dataReader: DataCallerAsyncReader = ...
  /// let fileWriter: FileCallerAsyncWriter = ...
  ///
  /// try await dataReader.pipe(bufferingInto: fileWriter, intermediateCapacity: 4096)
  /// ```
  ///
  /// - Parameters:
  ///   - writer: A ``CallerAsyncWriter`` to receive the elements. The writer
  ///     is consumed.
  ///   - intermediateCapacity: The capacity of the intermediate buffer that
  ///     mediates between the reader and writer.
  ///
  /// - Throws: An error originating from the read or write operations.
  public consuming func pipe<Writer>(
    bufferingInto writer: consuming Writer,
    intermediateCapacity: Int
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
  where
    Writer: CallerAsyncWriter & ~Copyable,
    Writer.WriteElement == ReadElement,
    Writer.FinalElement == FinalElement
  {
    var reader = self
    var writerOpt: Writer? = .some(writer)
    var buffer = UniqueArray<ReadElement>(minimumCapacity: intermediateCapacity)
    var done = false
    while !done {
      let final: FinalElement?
      do throws(ReadFailure) {
        final = try await reader.read(into: &buffer)
      } catch {
        throw .first(error)
      }
      if let final {
        let w = writerOpt.take()!
        do throws(Writer.WriteFailure) {
          try await w.finish(buffer: &buffer, finalElement: final)
        } catch {
          throw .second(error)
        }
        done = true
      } else if buffer.count > 0 {
        do throws(Writer.WriteFailure) {
          try await writerOpt!.write(buffer: &buffer)
          assert(buffer.count == 0, "CallerAsyncWriter must drain the buffer during write(buffer:)")
        } catch {
          throw .second(error)
        }
      }
    }
  }
}
#endif

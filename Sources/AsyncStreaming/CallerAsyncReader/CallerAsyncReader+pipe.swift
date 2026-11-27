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

public import SpanPreview

public import ContainersPreview

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

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension CallerAsyncReader
where Self: ~Copyable, Self: ~Escapable, Self.ReadElement: ~Copyable, Self.FinalElement: ~Copyable {
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
    Writer.FinalElement == FinalElement,
    Writer.WriteElement: ~Copyable,
    Writer.FinalElement: ~Copyable
  {
    var reader = self
    var writerOpt: Writer? = .some(writer)
    var done = false
    while !done {
      var pendingFinal: FinalElement? = nil
      try await writerOpt!
        .write { (output: inout OutputSpan<Writer.WriteElement>) throws(ReadFailure) -> Void in
          pendingFinal = try await reader.read(into: &output)
        }
      if let final = pendingFinal.take() {
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
  /// with the writer's ``CallerAsyncWriter/finish(_:finalElement:)``.
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
    Writer.FinalElement == FinalElement,
    Writer.WriteElement: ~Copyable,
    Writer.FinalElement: ~Copyable
  {
    precondition(intermediateCapacity > 0, "intermediateCapacity must be positive")
    var reader = self
    var writerOpt: Writer? = .some(writer)
    let storage = UnsafeMutableBufferPointer<ReadElement>.allocate(capacity: intermediateCapacity)
    defer { unsafe storage.deallocate() }
    var done = false
    while !done {
      var output = unsafe OutputSpan(buffer: storage, initializedCount: 0)
      let final: FinalElement?
      do throws(ReadFailure) {
        final = try await reader.read(into: &output)
      } catch {
        let count = unsafe output.finalize(for: storage)
        unsafe storage.baseAddress.unsafelyUnwrapped.deinitialize(count: count)
        throw .first(error)
      }
      let count = unsafe output.finalize(for: storage)
      // The writer takes the elements out of the buffer. It leaves elements
      // behind only when it throws, and these are destroyed here.
      let filled = unsafe UnsafeMutableBufferPointer(start: storage.baseAddress, count: count)
      var elements = unsafe InputSpan(buffer: filled, initializedCount: count)
      var failure: Writer.WriteFailure? = nil
      switch consume final {
      case .some(let final):
        let w = writerOpt.take()!
        do throws(Writer.WriteFailure) {
          try await w.finish(&elements, finalElement: final)
        } catch {
          failure = error
        }
        done = true
      case .none:
        if count > 0 {
          do throws(Writer.WriteFailure) {
            try await writerOpt!.write(&elements)
          } catch {
            failure = error
          }
        }
      }
      let remaining = unsafe elements.finalize(for: filled)
      if remaining > 0 {
        unsafe (filled.baseAddress.unsafelyUnwrapped + (count - remaining)).deinitialize(count: remaining)
      }
      if let failure {
        throw .second(failure)
      }
    }
  }
}
#endif

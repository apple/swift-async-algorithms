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

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable, ReadElement: ~Copyable, FinalElement: ~Copyable {
  /// Moves all elements of this reader into a caller-owned writer and fuses
  /// the terminal chunk with the writer's `finish`.
  ///
  /// The writer takes ownership of each chunk through
  /// the `InputSpan` overload of ``CallerAsyncWriter/write(_:)``, so no element is copied.
  ///
  /// - Parameter writer: Receives the elements. The writer is consumed.
  /// - Throws: An error from the read or the write operations.
  public consuming func pipe<Writer>(
    into writer: consuming Writer
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
  where
    Writer: CallerAsyncWriter & ~Copyable,
    Writer.WriteElement == ReadElement,
    Writer.FinalElement == FinalElement,
    Writer.WriteElement: ~Copyable,
    Writer.FinalElement: ~Copyable
  {
    var reader = self
    var writerOpt: Writer? = .some(writer)
    var done = false
    while !done {
      try await reader.read {
        (
          elements: inout InputSpan<ReadElement>,
          finalElement: consuming FinalElement?
        ) throws(Writer.WriteFailure)
          -> Void in
        switch consume finalElement {
        case .some(let finalElement):
          let w = writerOpt.take()!
          try await w.finish(&elements, finalElement: finalElement)
          done = true
        case .none:
          try await writerOpt!.write(&elements)
        }
      }
    }
  }

  /// Moves all elements of this reader into a callee-owned writer.
  ///
  /// Each chunk moves from the reader's span into the output spans of the
  /// writer, so every element is moved once between the two buffers.
  ///
  /// - Parameter writer: Receives the elements. The writer is consumed.
  /// - Throws: An error from the read or the write operations.
  public consuming func pipe<Writer>(
    movingInto writer: consuming Writer
  ) async throws(EitherError<ReadFailure, Writer.WriteFailure>)
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
      try await reader.read {
        (
          elements: inout InputSpan<ReadElement>,
          finalElement: consuming FinalElement?
        ) throws(Writer.WriteFailure)
          -> Void in
        try await Self.move(&elements, into: &writerOpt!)
        switch consume finalElement {
        case .some(let finalElement):
          let w = writerOpt.take()!
          try await w.finish(finalElement: finalElement)
          done = true
        case .none:
          break
        }
      }
    }
  }

  private static func move<Writer>(
    _ elements: inout InputSpan<ReadElement>,
    into writer: inout Writer
  ) async throws(Writer.WriteFailure)
  where
    Writer: AsyncWriter & ~Copyable,
    Writer.WriteElement == ReadElement,
    Writer.WriteElement: ~Copyable,
    Writer.FinalElement: ~Copyable
  {
    while !elements.isEmpty {
      do throws(EitherError<Writer.WriteFailure, Never>) {
        try await writer.write { (output: inout OutputSpan<ReadElement>) in
          let count = output.append(moving: &elements)
          precondition(count > 0, "AsyncWriter provided an output span without free capacity")
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

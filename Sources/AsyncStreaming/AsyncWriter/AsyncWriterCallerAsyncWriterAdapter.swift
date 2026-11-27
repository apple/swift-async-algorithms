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

/// A ``CallerAsyncWriter`` that is implemented in terms of an
/// ``AsyncWriter``.
///
/// Each ``write(_:)`` call drains the caller's elements through one
/// or more ``AsyncWriter/write(_:)`` closures on the underlying writer.
/// When the underlying writer's buffer fills before the caller's empties,
/// the adapter loops with another closure call to continue draining.
///
/// The adapter introduces no buffer of its own — elements move directly
/// from the caller-supplied span into the underlying writer's
/// closure-supplied buffer. The underlying writer's deferred-flush
/// behavior, if any, is preserved.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
public struct AsyncWriterCallerAsyncWriterAdapter<
  Underlying: AsyncWriter & ~Copyable
>: ~Copyable, CallerAsyncWriter where Underlying.WriteElement: Copyable {
  public typealias WriteElement = Underlying.WriteElement
  public typealias WriteFailure = Underlying.WriteFailure
  public typealias FinalElement = Underlying.FinalElement

  @usableFromInline
  var underlying: Underlying

  @inlinable
  init(underlying: consuming Underlying) {
    self.underlying = underlying
  }

  @inlinable
  public mutating func write(_ elements: Span<WriteElement>) async throws(WriteFailure) {
    var offset = 0
    while offset < elements.count {
      do throws(EitherError<WriteFailure, Never>) {
        try await self.underlying.write { (output: inout OutputSpan<WriteElement>) async throws(Never) -> Void in
          let count = Swift.min(output.freeCapacity, elements.count - offset)
          precondition(count > 0, "AsyncWriter provided an output span without free capacity")
          output.append(copying: elements.extracting(offset..<(offset + count)))
          offset += count
        }
      } catch {
        switch error {
        case .first(let writeFailure): throw writeFailure
        case .second: fatalError("Unreachable")
        }
      }
    }
  }

  @inlinable
  public mutating func write(_ elements: inout InputSpan<WriteElement>) async throws(WriteFailure) {
    while !elements.isEmpty {
      do throws(EitherError<WriteFailure, Never>) {
        try await self.underlying.write { (output: inout OutputSpan<WriteElement>) async throws(Never) -> Void in
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

  @inlinable
  public consuming func finish(
    _ elements: inout InputSpan<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) {
    try await self.write(&elements)
    try await self.underlying.finish(finalElement: finalElement)
  }

  @inlinable
  public consuming func finish(
    _ elements: Span<WriteElement>,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) {
    try await self.write(elements)
    try await self.underlying.finish(finalElement: finalElement)
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension AsyncWriter where Self: ~Copyable, WriteElement: Copyable {
  /// Adapts this ``AsyncWriter`` to a ``CallerAsyncWriter``.
  ///
  /// The returned adapter accepts caller-supplied spans via
  /// ``CallerAsyncWriter/write(_:)`` and copies them through this
  /// writer's closure-based ``AsyncWriter/write(_:)``. When this
  /// writer's output span fills before the caller's span empties, the
  /// adapter loops with another closure call.
  ///
  /// The adapter introduces no buffer of its own.
  ///
  /// - Returns: An adapter that conforms to ``CallerAsyncWriter``.
  @inlinable
  public consuming func asCallerAsyncWriter() -> AsyncWriterCallerAsyncWriterAdapter<Self> {
    .init(underlying: self)
  }
}
#endif

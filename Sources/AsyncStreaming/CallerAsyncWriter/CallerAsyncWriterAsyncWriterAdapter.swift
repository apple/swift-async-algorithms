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
public import BasicContainers

/// An ``AsyncWriter`` that is implemented in terms of a ``CallerAsyncWriter``.
///
/// The adapter allocates a fresh buffer for each ``write(_:)`` call, runs
/// the body to fill it, and immediately drains it into the underlying
/// ``CallerAsyncWriter``. Writes are flushed *eagerly*: the adapter does
/// not defer the most recent buffer to fuse it with ``finish(finalElement:)``.
///
/// Eager flushing keeps request/response patterns deadlock-free — a write
/// is observable to the peer as soon as the underlying writer accepts it.
/// The trade-off is that fused close (HTTP/2 DATA+END_STREAM coalescing,
/// and similar) is not available through this adapter; the underlying
/// ``CallerAsyncWriter/finish(buffer:finalElement:)`` always receives an
/// empty buffer. Conformers that need fused close should implement
/// ``AsyncWriter`` directly rather than going through this adapter.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct CallerAsyncWriterAsyncWriterAdapter<
  Underlying: CallerAsyncWriter & ~Copyable,
  Buffer: DynamicContainer<Underlying.WriteElement> & ~Copyable
>: ~Copyable, AsyncWriter {
  public typealias WriteElement = Underlying.WriteElement
  public typealias WriteFailure = Underlying.WriteFailure
  public typealias FinalElement = Underlying.FinalElement

  @usableFromInline
  var underlying: Underlying

  @usableFromInline
  let initialCapacity: Int

  @inlinable
  init(underlying: consuming Underlying, initialCapacity: Int) {
    self.underlying = underlying
    self.initialCapacity = initialCapacity
  }

  @inlinable
  public mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout Buffer) async throws(Failure) -> Return
  ) async throws(EitherError<WriteFailure, Failure>) -> Return {
    var buffer = Buffer(minimumCapacity: self.initialCapacity)
    let result: Return
    do throws(Failure) {
      result = try await body(&buffer)
    } catch {
      throw .second(error)
    }
    do throws(WriteFailure) {
      try await self.underlying.write(buffer: &buffer)
    } catch {
      throw .first(error)
    }
    return result
  }

  @inlinable
  public consuming func finish(
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) {
    var empty = Buffer()
    try await self.underlying.finish(buffer: &empty, finalElement: finalElement)
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension CallerAsyncWriter where Self: ~Copyable {
  /// Adapts this ``CallerAsyncWriter`` to an ``AsyncWriter``, using
  /// ``UniqueArray`` as the buffer container.
  ///
  /// Each ``AsyncWriter/write(_:)`` call on the returned adapter
  /// allocates a fresh buffer, runs the closure to fill it, and
  /// immediately drains it into this writer. Writes are flushed
  /// eagerly — see ``CallerAsyncWriterAsyncWriterAdapter`` for the
  /// trade-off this implies for fused close.
  ///
  /// - Parameter initialCapacity: The capacity reserved on each
  ///   freshly allocated buffer.
  /// - Returns: An adapter that conforms to ``AsyncWriter``.
  @inlinable
  public consuming func asAsyncWriter(
    initialCapacity: Int = 4096
  ) -> CallerAsyncWriterAsyncWriterAdapter<Self, UniqueArray<WriteElement>> {
    .init(underlying: self, initialCapacity: initialCapacity)
  }

  /// Adapts this ``CallerAsyncWriter`` to an ``AsyncWriter`` with a
  /// caller-chosen buffer container type.
  ///
  /// - Parameters:
  ///   - bufferType: The container type for buffers handed to the
  ///     ``AsyncWriter/write(_:)`` body.
  ///   - initialCapacity: The capacity reserved on each freshly
  ///     allocated buffer.
  /// - Returns: An adapter that conforms to ``AsyncWriter``.
  @inlinable
  public consuming func asAsyncWriter<Buffer>(
    bufferOf bufferType: Buffer.Type,
    initialCapacity: Int = 4096
  ) -> CallerAsyncWriterAsyncWriterAdapter<Self, Buffer>
  where Buffer: DynamicContainer<WriteElement> & ~Copyable {
    .init(underlying: self, initialCapacity: initialCapacity)
  }
}
#endif

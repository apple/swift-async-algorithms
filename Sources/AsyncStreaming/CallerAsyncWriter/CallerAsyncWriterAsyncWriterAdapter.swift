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

/// An ``AsyncWriter`` that is implemented in terms of a ``CallerAsyncWriter``.
///
/// The adapter owns one buffer. For each ``write(_:)`` call it lends the
/// buffer to the body as an `OutputSpan`, and immediately passes the
/// elements that the body appended to the underlying ``CallerAsyncWriter``.
/// Writes are flushed *eagerly*: the adapter does not defer the most recent
/// elements to fuse them with ``finish(finalElement:)``.
///
/// Eager flushing keeps request/response patterns deadlock-free — a write
/// is observable to the peer as soon as the underlying writer accepts it.
/// The trade-off is that fused close (HTTP/2 DATA+END_STREAM coalescing,
/// and similar) is not available through this adapter; the underlying
/// ``CallerAsyncWriter/finish(_:finalElement:)`` always receives no
/// elements. Conformers that need fused close should implement
/// ``AsyncWriter`` directly rather than going through this adapter.
/// Owns the memory that the adapter lends out as an output span.
@usableFromInline
final class _AdapterStorage<Element: ~Copyable>: @unchecked Sendable {
  @usableFromInline
  let storage: UnsafeMutableBufferPointer<Element>

  @usableFromInline
  init(capacity: Int) {
    self.storage = unsafe .allocate(capacity: capacity)
  }

  deinit {
    unsafe self.storage.deallocate()
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
public struct CallerAsyncWriterAsyncWriterAdapter<
  Underlying: CallerAsyncWriter & ~Copyable
>: ~Copyable, AsyncWriter {
  public typealias WriteElement = Underlying.WriteElement
  public typealias WriteFailure = Underlying.WriteFailure
  public typealias FinalElement = Underlying.FinalElement

  @usableFromInline
  var underlying: Underlying

  @usableFromInline
  let owner: _AdapterStorage<Underlying.WriteElement>

  @inlinable
  init(underlying: consuming Underlying, capacity: Int) {
    precondition(capacity > 0, "capacity must be positive")
    self.underlying = underlying
    self.owner = _AdapterStorage(capacity: capacity)
  }

  @inlinable
  public mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout OutputSpan<Underlying.WriteElement>) async throws(Failure) -> Return
  ) async throws(EitherError<WriteFailure, Failure>) -> Return {
    var output = unsafe OutputSpan(buffer: self.owner.storage, initializedCount: 0)
    let result: Return
    do throws(Failure) {
      result = try await body(&output)
    } catch {
      let count = unsafe output.finalize(for: self.owner.storage)
      unsafe self.owner.storage.baseAddress.unsafelyUnwrapped.deinitialize(count: count)
      throw .second(error)
    }
    let count = unsafe output.finalize(for: self.owner.storage)
    // The underlying writer takes the elements. It leaves elements behind only
    // when it throws, and these are destroyed here.
    let filled = unsafe UnsafeMutableBufferPointer(start: self.owner.storage.baseAddress, count: count)
    var elements = unsafe InputSpan(buffer: filled, initializedCount: count)
    var failure: WriteFailure? = nil
    do throws(WriteFailure) {
      try await self.underlying.write(&elements)
    } catch {
      failure = error
    }
    let remaining = unsafe elements.finalize(for: filled)
    if remaining > 0 {
      unsafe (filled.baseAddress.unsafelyUnwrapped + (count - remaining)).deinitialize(count: remaining)
    }
    if let failure {
      throw .first(failure)
    }
    return result
  }

  @inlinable
  public consuming func finish(
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) {
    try await self.underlying.finish(Span<Underlying.WriteElement>(), finalElement: finalElement)
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension CallerAsyncWriter where Self: ~Copyable {
  /// Adapts this writer to an ``AsyncWriter``.
  ///
  /// - Parameter capacity: The number of elements that the output span of a
  ///   single ``AsyncWriter/write(_:)`` call can hold.
  @inlinable
  public consuming func asAsyncWriter(
    capacity: Int = 4096
  ) -> CallerAsyncWriterAsyncWriterAdapter<Self> {
    .init(underlying: self, capacity: capacity)
  }
}
#endif

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

/// A ``CallerAsyncWriter`` that is implemented in terms of an
/// ``AsyncWriter``.
///
/// Each ``write(buffer:)`` call drains the caller's buffer through one
/// or more ``AsyncWriter/write(_:)`` closures on the underlying writer.
/// When the underlying writer's buffer fills before the caller's empties,
/// the adapter loops with another closure call to continue draining.
///
/// The adapter introduces no buffer of its own — elements move directly
/// from the caller-supplied buffer into the underlying writer's
/// closure-supplied buffer. The underlying writer's deferred-flush
/// behavior, if any, is preserved.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct AsyncWriterCallerAsyncWriterAdapter<
  Underlying: AsyncWriter & ~Copyable
>: ~Copyable, CallerAsyncWriter {
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
  public mutating func write<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer
  ) async throws(WriteFailure) {
    var consumer = buffer.consumeAll()
    while let head = consumer.next() {
      var pending: WriteElement? = head
      do throws(EitherError<WriteFailure, Never>) {
        try await self.underlying.write {
          (innerBuffer: inout Underlying.Buffer) async throws(Never) -> Void in
          if case .some(let element) = pending.take() {
            innerBuffer.append(element)
          }
          while innerBuffer.freeCapacity > 0 {
            guard let element = consumer.next() else { return }
            innerBuffer.append(element)
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

  @inlinable
  public consuming func finish<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) {
    try await self.write(buffer: &buffer)
    try await self.underlying.finish(finalElement: finalElement)
  }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension AsyncWriter where Self: ~Copyable {
  /// Adapts this ``AsyncWriter`` to a ``CallerAsyncWriter``.
  ///
  /// The returned adapter accepts caller-supplied buffers via
  /// ``CallerAsyncWriter/write(buffer:)`` and drains them through this
  /// writer's closure-based ``AsyncWriter/write(_:)``. When this
  /// writer's buffer fills before the caller's empties, the adapter
  /// loops with another closure call.
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

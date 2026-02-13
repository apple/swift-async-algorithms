//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming
import BasicContainers

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable {
  /// Transforms elements read from this reader using the provided transformation function.
  ///
  /// This method creates a new async reader that applies the specified transformation to each
  /// element read from the underlying reader. The transformation is applied lazily as elements
  /// are read, maintaining the streaming nature of the operation.
  ///
  /// - Parameter transformation: An asynchronous closure that transforms each read element
  ///   of type `ReadElement` into a new element of type `MappedElement`.
  ///
  /// - Returns: A new ``AsyncReader`` that produces transformed elements of type `MappedElement`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var dataReader: SomeAsyncReader<UInt8, Never> = ...
  ///
  /// // Transform the spans into their element count
  /// var countReader = dataReader.map { span in
  ///     span.count
  /// }
  ///
  /// try await countReader.forEach { span in
  ///     print("Received chunk with \(span[0]) values")
  /// }
  /// ```
  @_lifetime(copy self)
  public consuming func map<MappedElement>(
    _ transformation: @escaping (borrowing ReadElement) async -> MappedElement
  ) -> some (AsyncReader<MappedElement, ReadFailure> & ~Copyable & ~Escapable) {
    return AsyncMapReader(base: self, transformation: transformation)
  }
}

/// An async reader that transforms elements from a base reader using a mapping function.
///
/// This internal reader type wraps another async reader and applies a transformation
/// to each element read from the base reader. The transformation is applied lazily
/// as elements are read, maintaining the streaming nature of the operation.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct AsyncMapReader<Base: AsyncReader & ~Copyable & ~Escapable, MappedElement: ~Copyable>: AsyncReader, ~Copyable,
  ~Escapable
{
  typealias ReadElement = MappedElement
  typealias ReadFailure = Base.ReadFailure

  var base: Base
  var transformation: (borrowing Base.ReadElement) async -> MappedElement

  @_lifetime(copy base)
  init(
    base: consuming Base,
    transformation: @escaping (borrowing Base.ReadElement) async -> MappedElement
  ) {
    self.base = base
    self.transformation = transformation
  }

  #if compiler(<6.3)
  @_lifetime(&self)
  #endif
  mutating func read<Return, Failure>(
    maximumCount: Int?,
    body: (consuming Span<MappedElement>) async throws(Failure) -> Return
  ) async throws(EitherError<Base.ReadFailure, Failure>) -> Return {
    var buffer = RigidArray<MappedElement>()
    return try await self.base
      .read(maximumCount: maximumCount) { (span) throws(Failure) -> Return in
        guard span.count > 0 else {
          let emptySpan = InlineArray<0, MappedElement>.zero()
          return try await body(emptySpan.span)
        }

        buffer.reserveCapacity(span.count)

        for index in span.indices {
          let transformed = await self.transformation(span[index])
          buffer.append(transformed)
        }

        return try await body(buffer.span)
      }
  }
}
#endif

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

/// Writes elements asynchronously from a caller-provided buffer.
///
/// Adopt ``CallerAsyncWriter`` when you need caller-managed buffering,
/// where the caller provides a buffer of elements for the writer
/// to consume.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, *)
public protocol CallerAsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
  /// The type of elements this writer writes.
  associatedtype WriteElement: ~Copyable

  /// The error type that writing operations throw.
  associatedtype WriteFailure: Error

  /// Writes elements from the provided buffer to the underlying destination.
  ///
  /// This method asynchronously writes all elements from the provided buffer to the destination
  /// the writer represents.
  ///
  /// - Parameter buffer: The buffer of elements to write.
  ///
  /// - Throws: A `WriteFailure` from the underlying write operation.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var fileWriter: FileAsyncWriter = ...
  /// var data = UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
  ///
  /// try await fileWriter.write(buffer: &data)
  /// ```
  mutating func write<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer
  ) async throws(WriteFailure) where Buffer.Element: ~Copyable
}
#endif

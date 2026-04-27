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
/// Reads elements asynchronously into a caller-provided buffer.
///
/// Adopt ``CallerAsyncReader`` when you need caller-managed buffering,
/// where the caller supplies an output span that the reader fills
/// with elements.
@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, visionOS 1.0, *)
public protocol CallerAsyncReader<ReadElement, ReadFailure>: ~Copyable, ~Escapable {
  /// The type of elements this reader reads.
  associatedtype ReadElement: ~Copyable

  /// The error type that reading operations throw.
  associatedtype ReadFailure: Error

  /// Reads elements from the source into the provided buffer.
  ///
  /// This method appends elements into `buffer`. When the read operation
  /// reaches the end of the source, it appends no elements.
  ///
  /// - Parameter buffer: The output span to fill with read elements.
  /// - Throws: A `ReadFailure` from the underlying read operation.
  mutating func read(
    into buffer: inout OutputSpan<ReadElement>
  ) async throws(ReadFailure)
}
#endif

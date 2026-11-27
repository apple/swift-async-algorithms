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
import AsyncStreaming
import BasicContainers
import ContainersPreview
import SpanPreview

/// Delivers its storage in chunks of at most `maxCount` elements and fuses the
/// last chunk with the end of the stream.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct UniqueArrayAsyncReader: ~Copyable, AsyncReader {
  typealias ReadElement = Int
  typealias ReadFailure = Never
  typealias FinalElement = Void

  var storage: UniqueArray<Int>
  var didEmitFinal: Bool = false

  mutating func read<Return: ~Copyable, Failure: Error>(
    maxCount: Int,
    body: (inout InputSpan<Int>, Void?) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    precondition(!self.didEmitFinal, "read called after end-of-stream")
    precondition(maxCount > 0, "maxCount must be greater than zero")
    let count = min(maxCount, self.storage.count)
    let isLast = count == self.storage.count
    self.didEmitFinal = isLast
    var chunk = UniqueArray<Int>(minimumCapacity: count)
    self.storage.consumeSubrange(0..<count) { elements in
      chunk.append(addingCount: count) { output in
        output.append(moving: &elements)
      }
    }
    do {
      return try await chunk.consumeAll { (elements: inout InputSpan<Int>) async throws(Failure) -> Return in
        try await body(&elements, isLast ? .some(()) : nil)
      }
    } catch {
      throw .second(error)
    }
  }
}
#endif

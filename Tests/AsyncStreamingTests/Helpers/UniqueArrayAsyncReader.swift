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
import _AsyncStreaming
import BasicContainers
import ContainersPreview

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct UniqueArrayAsyncReader: ~Copyable, AsyncReader {
  typealias ReadElement = Int
  typealias ReadFailure = Never

  var storage: UniqueArray<Int>

  mutating func read<Return, Failure: Error>(
    maximumCount: Int,
    body: (consuming InputSpan<Int>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    do {
      print(self.storage.count)
      guard storage.count > 0 else {
        return try await body(InputSpan<Int>())
      }

      let count = min(maximumCount, storage.count)

      // Use the callback-based consume which correctly updates storage's count.
      var chunk = UniqueArray<Int>(capacity: count)
      self.storage.consume(0..<count, consumingWith: { inputSpan in
        chunk.append(moving: &inputSpan)
      })
      print(chunk[0])

      // Drain the local chunk to get InputSpan for the async body.
      var consumer = chunk.consume(chunk.startIndex..<chunk.count)
      let inputSpan = consumer.drainNext(maximumCount: .max)
      return try await body(inputSpan)
    } catch {
      throw .second(error)
    }
  }
}
#endif

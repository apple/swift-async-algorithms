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

/// An ``AsyncReader`` that delivers `chunks` one per `read`, as
/// ``NoncopyableInt`` elements, and passes `finalElement` with the last chunk.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct UniqueArrayAsyncReader<FinalElement: ~Copyable>: ~Copyable, AsyncReader {
  typealias ReadElement = NoncopyableInt
  typealias Buffer = UniqueArray<NoncopyableInt>
  typealias ReadFailure = Never

  let chunks: [[Int]]
  let tracker: LifetimeTracker?
  var nextChunk = 0
  var finalElement: FinalElement?

  init(chunks: [[Int]], finalElement: consuming FinalElement, tracker: LifetimeTracker? = nil) {
    precondition(!chunks.isEmpty, "a reader delivers at least one chunk")
    self.chunks = chunks
    self.tracker = tracker
    self.finalElement = .some(finalElement)
  }

  init(values: [Int], finalElement: consuming FinalElement, tracker: LifetimeTracker? = nil) {
    self.init(chunks: [values], finalElement: finalElement, tracker: tracker)
  }

  mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout UniqueArray<NoncopyableInt>, consuming FinalElement?) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    precondition(self.nextChunk < self.chunks.count, "read called after end-of-stream")
    var buffer = UniqueArray(values: self.chunks[self.nextChunk], tracker: self.tracker)
    self.nextChunk += 1
    let final: FinalElement? = self.nextChunk == self.chunks.count ? self.finalElement.take() : nil
    do {
      return try await body(&buffer, final)
    } catch {
      throw .second(error)
    }
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension UniqueArrayAsyncReader where FinalElement == Void {
  init(chunks: [[Int]], tracker: LifetimeTracker? = nil) {
    self.init(chunks: chunks, finalElement: (), tracker: tracker)
  }

  init(values: [Int], tracker: LifetimeTracker? = nil) {
    self.init(chunks: [values], finalElement: (), tracker: tracker)
  }
}
#endif

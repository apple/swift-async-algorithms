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
import Testing

@Suite
struct AsyncReaderPipeTests {
  // MARK: - pipe(into:) — into a CallerAsyncWriter

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoCopiesAllElements() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    try await UniqueArrayAsyncReader(values: [1, 2, 3, 4, 5], tracker: tracker)
      .pipe(into: UniqueArrayCallerAsyncWriter(sink: sink))

    #expect(sink.values == [1, 2, 3, 4, 5])
    #expect(sink.finished)
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoWithEmptyReader() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    try await UniqueArrayAsyncReader(values: [], tracker: tracker)
      .pipe(into: UniqueArrayCallerAsyncWriter(sink: sink))

    #expect(sink.values.isEmpty)
    #expect(sink.finished)
    #expect(tracker.created == 0)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoPreservesElementOrder() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let elements = Array(1...50)
    let chunks = stride(from: 0, to: elements.count, by: 10).map { start in
      Array(elements[start..<min(start + 10, elements.count)])
    }
    try await UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      .pipe(into: UniqueArrayCallerAsyncWriter(sink: sink))

    #expect(sink.values == elements)
    #expect(sink.finished)
    #expect(tracker.created == 50)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoWritesThenFinishesAcrossChunks() async throws {
    // A multi-chunk reader drives both the mid-stream `write(buffer:)` and the
    // terminal `finish(buffer:finalElement:)` paths.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    try await UniqueArrayAsyncReader(chunks: [[1, 2], [3]], tracker: tracker)
      .pipe(into: UniqueArrayCallerAsyncWriter(sink: sink))

    #expect(sink.values == [1, 2, 3])
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  // MARK: - pipe(copyingInto:) — into an AsyncWriter

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeCopyingIntoCopiesAllElements() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    try await UniqueArrayAsyncReader(values: [1, 2, 3, 4, 5], tracker: tracker)
      .pipe(copyingInto: UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter())

    #expect(sink.values == [1, 2, 3, 4, 5])
    #expect(sink.finished)
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeCopyingIntoWithEmptyReader() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    try await UniqueArrayAsyncReader(values: [], tracker: tracker)
      .pipe(copyingInto: UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter())

    #expect(sink.values.isEmpty)
    #expect(sink.finished)
    #expect(tracker.created == 0)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeCopyingIntoChunksTerminalChunkAcrossMultipleWrites() async throws {
    // 200 elements through a small (16-element) AsyncWriter buffer
    // forces the pipe loop to drain across multiple writes.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let elements = Array(1...200)
    try await UniqueArrayAsyncReader(values: elements, tracker: tracker)
      .pipe(copyingInto: UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter(initialCapacity: 16))

    #expect(sink.values == elements)
    #expect(sink.finished)
    #expect(tracker.created == 200)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeCopyingIntoWritesThenFinishesAcrossChunks() async throws {
    // A multi-chunk reader drives the drain-only path for the mid-stream chunk
    // and the drain-then-`finish(finalElement:)` path for the terminal chunk,
    // into an AsyncWriter used directly rather than through the adapter.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    try await UniqueArrayAsyncReader(chunks: [[1, 2], [3]], tracker: tracker)
      .pipe(copyingInto: UniqueArrayAsyncWriter(sink: sink))

    #expect(sink.values == [1, 2, 3])
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}
#endif

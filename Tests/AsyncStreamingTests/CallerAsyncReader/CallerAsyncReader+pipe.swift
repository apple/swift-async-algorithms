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
struct CallerAsyncReaderPipeTests {
  // MARK: - pipe(into:) — into an AsyncWriter via the adapter

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoCopiesAllElements() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let source = UniqueArrayCallerAsyncReader(values: [1, 2, 3, 4, 5], tracker: tracker)
    try await source.pipe(into: UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter())

    #expect(sink.values == [1, 2, 3, 4, 5])
    #expect(sink.finished)
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoWithEmptyReader() async throws {
    let sink = WriteSink<Void>()

    let source = UniqueArrayCallerAsyncReader(values: [])
    try await source.pipe(into: UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter())

    #expect(sink.values.isEmpty)
    #expect(sink.finished)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoLoopsAcrossMultipleBuffers() async throws {
    // 200 elements through a small AsyncWriter buffer forces the pipe
    // loop to iterate multiple times.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let elements = Array(1...200)
    let source = UniqueArrayCallerAsyncReader(values: elements, tracker: tracker)
    try await source.pipe(
      into: UniqueArrayCallerAsyncWriter(capacity: 200, sink: sink).asAsyncWriter(initialCapacity: 16)
    )

    #expect(sink.values == elements)
    #expect(sink.finished)
    #expect(tracker.created == 200)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoAsyncWriter() async throws {
    // Pipes straight into an AsyncWriter, with no adapter in between. The
    // reader delivers at most two elements per read, so pipe writes [1, 2]
    // and then [3], and finishes with the final element from the last read.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let source = UniqueArrayCallerAsyncReader(values: [1, 2, 3], maximumChunkSize: 2, tracker: tracker)
    try await source.pipe(into: UniqueArrayAsyncWriter(sink: sink))

    #expect(sink.values == [1, 2, 3])
    #expect(sink.writes == 2)
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  // MARK: - pipe(bufferingInto:) — into a CallerAsyncWriter

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeBufferingIntoCopiesAllElements() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let source = UniqueArrayCallerAsyncReader(values: [1, 2, 3, 4, 5], tracker: tracker)
    try await source.pipe(bufferingInto: UniqueArrayCallerAsyncWriter(sink: sink), intermediateCapacity: 16)

    #expect(sink.values == [1, 2, 3, 4, 5])
    #expect(sink.finished)
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeBufferingIntoWithEmptyReader() async throws {
    let sink = WriteSink<Void>()

    let source = UniqueArrayCallerAsyncReader(values: [])
    try await source.pipe(bufferingInto: UniqueArrayCallerAsyncWriter(sink: sink), intermediateCapacity: 16)

    #expect(sink.values.isEmpty)
    #expect(sink.finished)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeBufferingIntoReusesIntermediateBufferAcrossMultipleIterations() async throws {
    // 100 elements through a 16-element intermediate buffer forces the
    // pipe loop to iterate the buffer many times.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let elements = Array(1...100)
    let source = UniqueArrayCallerAsyncReader(values: elements, tracker: tracker)
    try await source.pipe(bufferingInto: UniqueArrayCallerAsyncWriter(sink: sink), intermediateCapacity: 16)

    #expect(sink.values == elements)
    #expect(sink.finished)
    #expect(tracker.created == 100)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeBufferingIntoSplitsAcrossWriteAndFinish() async throws {
    // The reader delivers at most two elements per read, so [1, 2] goes
    // through write and [3] through finish.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let source = UniqueArrayCallerAsyncReader(values: [1, 2, 3], maximumChunkSize: 2, tracker: tracker)
    try await source.pipe(bufferingInto: UniqueArrayCallerAsyncWriter(sink: sink), intermediateCapacity: 2)

    #expect(sink.values == [1, 2, 3])
    #expect(sink.writes == 1)
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}
#endif

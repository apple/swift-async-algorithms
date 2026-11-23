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
struct CallerAsyncWriterAsyncWriterAdapterTests {
  // The adapter wraps a CallerAsyncWriter and exposes an AsyncWriter, so
  // we drive it through the AsyncWriter side and verify the elements
  // arrive in the underlying CallerAsyncWriter's sink.

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeAndFinishRoundTrip() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    var asyncWriter = UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter()
    try await asyncWriter.write { buffer in
      buffer.append(NoncopyableInt(1, tracker: tracker))
      buffer.append(NoncopyableInt(2, tracker: tracker))
      buffer.append(NoncopyableInt(3, tracker: tracker))
    }
    await asyncWriter.finish()

    #expect(sink.values == [1, 2, 3])
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func multipleWritesAreFlushedEagerly() async throws {
    // The adapter must NOT defer the most recent write — each write call
    // should flush before returning, so the peer can observe progress
    // before close. We verify by checking the underlying writer's sink
    // after each write.
    let sink = WriteSink<Void>()

    var asyncWriter = UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter()

    try await asyncWriter.write { $0.append(NoncopyableInt(10)) }
    // The underlying writer sees the first write before any second write
    // or finish.
    #expect(sink.values == [10])
    #expect(!sink.finished)

    try await asyncWriter.write { $0.append(NoncopyableInt(20)) }
    #expect(sink.values == [10, 20])
    #expect(!sink.finished)

    await asyncWriter.finish()
    // Finish adds no elements; it only delivers the final element.
    #expect(sink.values == [10, 20])
    #expect(sink.finished)
    #expect(sink.finalElement != nil)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishWithoutWriteDeliversEmptyTerminator() async throws {
    let sink = WriteSink<Void>()

    let asyncWriter = UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter()
    await asyncWriter.finish()

    #expect(sink.values.isEmpty)
    #expect(sink.finished)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func customBufferTypePreservesElements() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    var asyncWriter = UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter(
      bufferOf: UniqueArray<NoncopyableInt>.self,
      initialCapacity: 16
    )
    try await asyncWriter.write { buffer in
      for value in 1...5 { buffer.append(NoncopyableInt(value, tracker: tracker)) }
    }
    await asyncWriter.finish()

    #expect(sink.values == [1, 2, 3, 4, 5])
    #expect(sink.finished)
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asAsyncWriter() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let writer:
      CallerAsyncWriterAsyncWriterAdapter<
        UniqueArrayCallerAsyncWriter<Void>, UniqueArray<NoncopyableInt>
      > = UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter(initialCapacity: 2)
    try await UniqueArrayAsyncReader(chunks: [[1, 2], [3]], tracker: tracker).pipe(copyingInto: writer)

    #expect(sink.values == [1, 2, 3])
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asAsyncWriterBufferOf() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let writer:
      CallerAsyncWriterAsyncWriterAdapter<
        UniqueArrayCallerAsyncWriter<Void>, UniqueArray<NoncopyableInt>
      > = UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter(
        bufferOf: UniqueArray<NoncopyableInt>.self,
        initialCapacity: 2
      )
    // The reader delivers at most two elements per read, so the adapter
    // flushes [1, 2] and then [3] to the underlying writer before finishing.
    try await UniqueArrayCallerAsyncReader(values: [1, 2, 3], maximumChunkSize: 2, tracker: tracker)
      .pipe(into: writer)

    #expect(sink.values == [1, 2, 3])
    #expect(sink.writes == 2)
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}

/// The adapter passes a noncopyable final element on to the underlying
/// writer's `finish`.
@Suite
struct CallerAsyncWriterAsyncWriterAdapterFinalElementTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishDeliversNoncopyableFinalElement() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<NoncopyableInt>()

    var writer = UniqueArrayCallerAsyncWriter(sink: sink).asAsyncWriter()
    try await writer.write { buffer in
      buffer.append(NoncopyableInt(1, tracker: tracker))
      buffer.append(NoncopyableInt(2, tracker: tracker))
    }
    await writer.finish(finalElement: NoncopyableInt(99, tracker: tracker))

    #expect(sink.values == [1, 2])
    #expect(sink.finished)
    #expect(sink.finalValue == 99)
    sink.finalElement = nil
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}
#endif

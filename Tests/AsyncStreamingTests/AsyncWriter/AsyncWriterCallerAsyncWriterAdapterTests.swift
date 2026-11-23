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
struct AsyncWriterCallerAsyncWriterAdapterTests {
  // The adapter wraps an AsyncWriter and exposes a CallerAsyncWriter.
  // These tests wrap a UniqueArrayAsyncWriter via asCallerAsyncWriter(),
  // write through the adapter, and check what reached the writer's sink.

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeAndFinishRoundTrip() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()
    do {
      var callerWriter = UniqueArrayAsyncWriter(sink: sink).asCallerAsyncWriter()
      var buf = UniqueArray(values: [1, 2, 3], tracker: tracker)
      await callerWriter.write(buffer: &buf)
      var empty = UniqueArray<NoncopyableInt>()
      await callerWriter.finish(buffer: &empty, finalElement: ())
    }

    #expect(sink.values == [1, 2, 3])
    #expect(sink.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeLoopsAcrossMultipleUnderlyingBuffers() async throws {
    // The AsyncWriter underneath is a CallerAsyncWriterAsyncWriterAdapter,
    // which uses a 4096-element default buffer. We use a small
    // initialCapacity to force the inverse adapter to drive multiple
    // underlying writes.
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()
    let elements = Array(1...100)
    do {
      var callerWriter =
        UniqueArrayCallerAsyncWriter(sink: sink)
        .asAsyncWriter(initialCapacity: 16)
        .asCallerAsyncWriter()

      var buf = UniqueArray(values: elements, tracker: tracker)
      await callerWriter.write(buffer: &buf)
      var empty = UniqueArray<NoncopyableInt>()
      await callerWriter.finish(buffer: &empty, finalElement: ())
    }

    #expect(sink.values == elements)
    #expect(sink.finished)
    #expect(tracker.created == 100)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishWithoutWriteDeliversEmptyTerminator() async throws {
    let sink = WriteSink<Void>()

    let callerWriter = UniqueArrayAsyncWriter(sink: sink).asCallerAsyncWriter()
    var empty = UniqueArray<NoncopyableInt>()
    await callerWriter.finish(buffer: &empty, finalElement: ())

    #expect(sink.values.count == 0)
    #expect(sink.finished)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishDeliversTrailingBufferAndPayload() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()
    do {
      let callerWriter = UniqueArrayAsyncWriter(sink: sink).asCallerAsyncWriter()
      var trailing = UniqueArray(values: [42, 43, 44], tracker: tracker)
      await callerWriter.finish(buffer: &trailing, finalElement: ())
    }

    #expect(sink.values == [42, 43, 44])
    #expect(sink.finished)
    #expect(sink.finalElement != nil)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asCallerAsyncWriter() async throws {
    // Pipe an AsyncReader that delivers two chunks into the adapter, so the
    // elements pass through both the adapter's write and its finish. The
    // underlying writer's 2-element buffer is exactly filled by [1, 2].
    let tracker = LifetimeTracker()
    let sink = WriteSink<Void>()

    let writer: AsyncWriterCallerAsyncWriterAdapter<UniqueArrayAsyncWriter<Void>> =
      UniqueArrayAsyncWriter(bufferCapacity: 2, sink: sink).asCallerAsyncWriter()
    try await UniqueArrayAsyncReader(chunks: [[1, 2], [3]], tracker: tracker).pipe(into: writer)

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
struct AsyncWriterCallerAsyncWriterAdapterFinalElementTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishDeliversNoncopyableFinalElement() async throws {
    let tracker = LifetimeTracker()
    let sink = WriteSink<NoncopyableInt>()

    var writer = UniqueArrayAsyncWriter(sink: sink).asCallerAsyncWriter()
    var head = UniqueArray(values: [1, 2], tracker: tracker)
    await writer.write(buffer: &head)
    var tail = UniqueArray(values: [3], tracker: tracker)
    await writer.finish(buffer: &tail, finalElement: NoncopyableInt(99, tracker: tracker))

    #expect(sink.values == [1, 2, 3])
    #expect(sink.finished)
    #expect(sink.finalValue == 99)
    sink.finalElement = nil
    #expect(tracker.created == 4)
    #expect(tracker.live == 0)
  }
}
#endif

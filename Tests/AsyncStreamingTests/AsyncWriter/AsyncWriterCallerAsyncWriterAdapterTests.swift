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
  // We can't get an AsyncWriter from the duplex directly (its Writer is
  // a CallerAsyncWriter), so we wrap the duplex's Writer first via
  // asAsyncWriter() to get an AsyncWriter, then wrap THAT via
  // asCallerAsyncWriter() to exercise this adapter end-to-end.

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writeAndFinishRoundTrip() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      var callerWriter = writerB.asAsyncWriter().asCallerAsyncWriter()
      var buf = UniqueArray(copying: [1, 2, 3])
      try await callerWriter.write(buffer: &buf)
      var empty = UniqueArray<Int>()
      try await callerWriter.finish(buffer: &empty, finalElement: ())

      try await readerA.collect(upTo: 5) { span in
        #expect(span.count == 3)
        #expect(span[0] == 1)
        #expect(span[1] == 2)
        #expect(span[2] == 3)
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writeLoopsAcrossMultipleUnderlyingBuffers() async throws {
    // The CallerAsyncWriterAsyncWriterAdapter underneath uses a
    // 4096-element default buffer. We use a small initialCapacity to
    // force the inverse adapter to drive multiple underlying writes.
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 32, high: 256)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      var callerWriter =
        writerB
        .asAsyncWriter(initialCapacity: 16)
        .asCallerAsyncWriter()

      let elements = Array(1...100)
      var buf = UniqueArray(copying: elements)
      try await callerWriter.write(buffer: &buf)
      var empty = UniqueArray<Int>()
      try await callerWriter.finish(buffer: &empty, finalElement: ())

      try await readerA.collect(upTo: 100) { span in
        #expect(span.count == 100)
        for i in 0..<100 {
          #expect(span[i] == elements[i])
        }
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func finishWithoutWriteDeliversEmptyTerminator() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let callerWriter = writerB.asAsyncWriter().asCallerAsyncWriter()
      var empty = UniqueArray<Int>()
      try await callerWriter.finish(buffer: &empty, finalElement: ())

      try await readerA.collect(upTo: 5) { span in
        #expect(span.count == 0)
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func finishDeliversTrailingBufferAndPayload() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let callerWriter = writerB.asAsyncWriter().asCallerAsyncWriter()
      var trailing = UniqueArray(copying: [42, 43, 44])
      try await callerWriter.finish(buffer: &trailing, finalElement: ())

      try await readerA.collect(upTo: 5) { span in
        #expect(span.count == 3)
        #expect(span[0] == 42)
        #expect(span[1] == 43)
        #expect(span[2] == 44)
      }
    }
  }
}
#endif

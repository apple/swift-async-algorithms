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
  // we drive it through the duplex's CallerAsyncWriter side and verify
  // the elements arrive on the peer reader.

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writeAndFinishRoundTrip() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      var asyncWriter = writerB.asAsyncWriter()
      try await asyncWriter.write { buffer in
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
      }
      try await asyncWriter.finish()

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
  func multipleWritesAreFlushedEagerly() async throws {
    // The adapter must NOT defer the most recent write — each write call
    // should flush before returning, so the peer can observe progress
    // before close. We verify by reading back after each write.
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      var readerA = readerA
      let writerB = writerB

      var asyncWriter = writerB.asAsyncWriter()

      try await asyncWriter.write { $0.append(10) }
      // Reader sees the first write before any second write or finish.
      try await readerA.read { buffer, _ in
        #expect(buffer.count == 1)
        var c = buffer.consumeAll()
        #expect(c.next() == 10)
      }

      try await asyncWriter.write { $0.append(20) }
      try await readerA.read { buffer, _ in
        #expect(buffer.count == 1)
        var c = buffer.consumeAll()
        #expect(c.next() == 20)
      }

      try await asyncWriter.finish()
      try await readerA.read { buffer, finalElement in
        #expect(buffer.count == 0)
        #expect(finalElement != nil)
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

      let asyncWriter = writerB.asAsyncWriter()
      try await asyncWriter.finish()

      try await readerA.collect(upTo: 5) { span in
        #expect(span.count == 0)
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func customBufferTypePreservesElements() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      var asyncWriter = writerB.asAsyncWriter(
        bufferOf: UniqueArray<Int>.self,
        initialCapacity: 16
      )
      try await asyncWriter.write { buffer in
        for v in 1...5 { buffer.append(v) }
      }
      try await asyncWriter.finish()

      try await readerA.collect(upTo: 5) { span in
        #expect(span.count == 5)
        for i in 0..<5 {
          #expect(span[i] == i + 1)
        }
      }
    }
  }
}
#endif

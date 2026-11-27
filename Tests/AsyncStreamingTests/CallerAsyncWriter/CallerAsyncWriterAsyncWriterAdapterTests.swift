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
import Testing

@Suite
struct CallerAsyncWriterAsyncWriterAdapterTests {
  // The adapter wraps a CallerAsyncWriter and exposes an AsyncWriter, so
  // we drive it through the duplex's CallerAsyncWriter side and verify
  // the elements arrive on the peer reader.

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeAndFinishRoundTrip() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      var asyncWriter = writerB.asAsyncWriter()
      try await asyncWriter.write { output in
        output.append(1)
        output.append(2)
        output.append(3)
      }
      try await asyncWriter.finish()

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(into: &target)
      #expect(Array(target.span) == [1, 2, 3])
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
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
      try await readerA.read { elements, _ in
        #expect(elements.count == 1)
        #expect(elements[0] == 10)
      }

      try await asyncWriter.write { $0.append(20) }
      try await readerA.read { elements, _ in
        #expect(elements.count == 1)
        #expect(elements[0] == 20)
      }

      try await asyncWriter.finish()
      try await readerA.read { elements, finalElement in
        #expect(elements.count == 0)
        #expect(finalElement != nil)
      }
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
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

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(into: &target)
      #expect(target.count == 0)
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func customCapacityPreservesElements() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      var asyncWriter = writerB.asAsyncWriter(capacity: 16)
      try await asyncWriter.write { output in
        for v in 1...5 { output.append(v) }
      }
      try await asyncWriter.finish()

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(target.span) == [1, 2, 3, 4, 5])
    }
  }
}
#endif

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
struct AsyncWriterCallerAsyncWriterAdapterTests {
  // The adapter wraps an AsyncWriter and exposes a CallerAsyncWriter.
  // We can't get an AsyncWriter from the duplex directly (its Writer is
  // a CallerAsyncWriter), so we wrap the duplex's Writer first via
  // asAsyncWriter() to get an AsyncWriter, then wrap THAT via
  // asCallerAsyncWriter() to exercise this adapter end-to-end.

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeAndFinishRoundTrip() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      var callerWriter = writerB.asAsyncWriter().asCallerAsyncWriter()
      let buf = [1, 2, 3]
      try await callerWriter.write(buf.span)
      try await callerWriter.finish(Span<Int>(), finalElement: ())

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(into: &target)
      #expect(Array(target.span) == [1, 2, 3])
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
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
        .asAsyncWriter(capacity: 16)
        .asCallerAsyncWriter()

      let elements = Array(1...100)
      let buf = elements
      try await callerWriter.write(buf.span)
      try await callerWriter.finish(Span<Int>(), finalElement: ())

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 100)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(target.span) == elements)
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

      let callerWriter = writerB.asAsyncWriter().asCallerAsyncWriter()
      try await callerWriter.finish(Span<Int>(), finalElement: ())

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(into: &target)
      #expect(target.count == 0)
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishDeliversTrailingBufferAndPayload() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let callerWriter = writerB.asAsyncWriter().asCallerAsyncWriter()
      let trailing = [42, 43, 44]
      try await callerWriter.finish(trailing.span, finalElement: ())

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(into: &target)
      #expect(Array(target.span) == [42, 43, 44])
    }
  }
}
#endif

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
struct CallerAsyncReaderPipeTests {
  // MARK: - pipe(into:) — into an AsyncWriter via the adapter

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoCopiesAllElements() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let source = UniqueArrayCallerAsyncReader(
        storage: UniqueArray(copying: [1, 2, 3, 4, 5])
      )
      try await source.pipe(into: writerB.asAsyncWriter())

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(target.span) == [1, 2, 3, 4, 5])
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoWithEmptyReader() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let source = UniqueArrayCallerAsyncReader(storage: UniqueArray<Int>())
      try await source.pipe(into: writerB.asAsyncWriter())

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(into: &target)
      #expect(target.count == 0)
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoLoopsAcrossMultipleBuffers() async throws {
    // 200 elements through a small AsyncWriter buffer forces the pipe
    // loop to iterate multiple times.
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 32, high: 256)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let elements = Array(1...200)
      let source = UniqueArrayCallerAsyncReader(
        storage: UniqueArray(copying: elements)
      )
      try await source.pipe(into: writerB.asAsyncWriter(capacity: 16))

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 200)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(target.span) == elements)
    }
  }

  // MARK: - pipe(bufferingInto:) — into a CallerAsyncWriter

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeBufferingIntoCopiesAllElements() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let source = UniqueArrayCallerAsyncReader(
        storage: UniqueArray(copying: [1, 2, 3, 4, 5])
      )
      try await source.pipe(bufferingInto: writerB, intermediateCapacity: 16)

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(target.span) == [1, 2, 3, 4, 5])
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeBufferingIntoWithEmptyReader() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let source = UniqueArrayCallerAsyncReader(storage: UniqueArray<Int>())
      try await source.pipe(bufferingInto: writerB, intermediateCapacity: 16)

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 5)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(into: &target)
      #expect(target.count == 0)
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeBufferingIntoReusesIntermediateBufferAcrossMultipleIterations() async throws {
    // 100 elements through a 16-element intermediate buffer forces the
    // pipe loop to iterate the buffer many times.
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 16, high: 200)
    ) { _, readerA, writerB, _ in
      let readerA = readerA
      let writerB = writerB

      let elements = Array(1...100)
      let source = UniqueArrayCallerAsyncReader(
        storage: UniqueArray(copying: elements)
      )
      try await source.pipe(bufferingInto: writerB, intermediateCapacity: 16)

      let targetStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 100)

      defer { targetStorage.deallocate() }

      var target = OutputSpan(buffer: targetStorage, initializedCount: 0)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(target.span) == elements)
    }
  }
}
#endif

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

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func pipeIntoCopiesAllElements() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      let readerA = readerA
      let writerB = writerB
      let readerB = readerB

      var array = UniqueArray(copying: [1, 2, 3, 4, 5])
      try await writerA.write(buffer: &array)
      writerA.finish()
      try await readerB.pipe(into: writerB)

      var target = RigidArray<Int>(capacity: 5)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(draining: &target) == [1, 2, 3, 4, 5])
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func pipeIntoWithEmptyReader() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { writerA, readerA, writerB, readerB in
      let writerA = writerA
      let readerA = readerA
      let writerB = writerB
      let readerB = readerB

      writerA.finish()
      try await readerB.pipe(into: writerB)

      var target = RigidArray<Int>(capacity: 5)
      try await readerA.collect(into: &target)
      #expect(target.count == 0)
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func pipeIntoPreservesElementOrder() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 16, high: 100)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      let readerA = readerA
      let writerB = writerB
      let readerB = readerB

      let elements = Array(1...50)
      var array = UniqueArray(copying: elements)
      try await writerA.write(buffer: &array)
      writerA.finish()
      try await readerB.pipe(into: writerB)

      var target = RigidArray<Int>(capacity: 50)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(draining: &target) == elements)
    }
  }

  // MARK: - pipe(copyingInto:) — into an AsyncWriter via the adapter

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func pipeCopyingIntoCopiesAllElements() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      let readerA = readerA
      let writerB = writerB
      let readerB = readerB

      var array = UniqueArray(copying: [1, 2, 3, 4, 5])
      try await writerA.write(buffer: &array)
      writerA.finish()
      try await readerB.pipe(copyingInto: writerB.asAsyncWriter())

      var target = RigidArray<Int>(capacity: 5)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(draining: &target) == [1, 2, 3, 4, 5])
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func pipeCopyingIntoWithEmptyReader() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 8, high: 32)
    ) { writerA, readerA, writerB, readerB in
      let writerA = writerA
      let readerA = readerA
      let writerB = writerB
      let readerB = readerB

      writerA.finish()
      try await readerB.pipe(copyingInto: writerB.asAsyncWriter())

      var target = RigidArray<Int>(capacity: 5)
      try await readerA.collect(into: &target)
      #expect(target.count == 0)
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func pipeCopyingIntoChunksTerminalChunkAcrossMultipleWrites() async throws {
    // 200 elements through a small (16-element) AsyncWriter buffer
    // forces the pipe loop to drain across multiple writes.
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 32, high: 256)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      let readerA = readerA
      let writerB = writerB
      let readerB = readerB

      let elements = Array(1...200)
      var array = UniqueArray(copying: elements)
      try await writerA.write(buffer: &array)
      writerA.finish()
      try await readerB.pipe(copyingInto: writerB.asAsyncWriter(initialCapacity: 16))

      var target = RigidArray<Int>(capacity: 200)
      try await readerA.collect(exactlyInto: &target)
      #expect(Array(draining: &target) == elements)
    }
  }
}
#endif

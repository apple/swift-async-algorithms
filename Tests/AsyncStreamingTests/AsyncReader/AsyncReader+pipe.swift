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
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeIntoCopiesAllElements() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    var writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(into: &writer)

    #expect(writer.storage.count == 5)
    #expect(writer.storage[0] == 1)
    #expect(writer.storage[1] == 2)
    #expect(writer.storage[2] == 3)
    #expect(writer.storage[3] == 4)
    #expect(writer.storage[4] == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeIntoWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray<Int>()
    )
    var writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(into: &writer)

    #expect(writer.storage.count == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeIntoPreservesElementOrder() async throws {
    let elements = Array(1...50)
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    var writer = UniqueArrayCallerAsyncWriter(capacity: elements.count)

    try await reader.pipe(into: &writer)

    #expect(writer.storage.count == elements.count)
    for i in 0..<elements.count {
      #expect(writer.storage[i] == elements[i])
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writerIntoRemainsUsableAfterPipe() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: 3, copying: [1, 2, 3])
    )
    var writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(into: &writer)

    var more = UniqueArray(capacity: 1, copying: [99])
    await writer.write(buffer: &more)

    #expect(writer.storage.count == 4)
    #expect(writer.storage[3] == 99)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeCopyingIntoCopiesAllElements() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    var writer = UniqueArrayAsyncWriter()

    try await reader.pipe(copyingInto: &writer)

    #expect(writer.storage.count == 5)
    #expect(writer.storage[0] == 1)
    #expect(writer.storage[1] == 2)
    #expect(writer.storage[2] == 3)
    #expect(writer.storage[3] == 4)
    #expect(writer.storage[4] == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeCopyingIntoWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray<Int>()
    )
    var writer = UniqueArrayAsyncWriter()

    try await reader.pipe(copyingInto: &writer)

    #expect(writer.storage.count == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeCopyingIntoChunksReaderBufferAcrossMultipleWrites() async throws {
    // Reader hands out a single 200-element buffer. The writer hands out 64-element
    // buffers, so the reader buffer must be drained across multiple writer.write calls.
    let elements = Array(1...200)
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    var writer = UniqueArrayAsyncWriter(capacity: 256)

    try await reader.pipe(copyingInto: &writer)

    #expect(writer.storage.count == elements.count)
    for i in 0..<elements.count {
      #expect(writer.storage[i] == elements[i])
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writerCopyingIntoRemainsUsableAfterPipe() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: 3, copying: [1, 2, 3])
    )
    var writer = UniqueArrayAsyncWriter()

    try await reader.pipe(copyingInto: &writer)

    try! await writer.write { buffer in
      buffer.append(99)
    }

    #expect(writer.storage.count == 4)
    #expect(writer.storage[3] == 99)
  }
}
#endif

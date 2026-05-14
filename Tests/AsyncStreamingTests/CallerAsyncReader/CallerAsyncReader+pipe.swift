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
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeIntoCopiesAllElements() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    var writer = UniqueArrayAsyncWriter()

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
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray<Int>()
    )
    var writer = UniqueArrayAsyncWriter()

    try await reader.pipe(into: &writer)

    #expect(writer.storage.count == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeIntoLoopsAcrossMultipleBuffers() async throws {
    // The writer hands out 64-element buffers. Use 200 elements to force the
    // implementation to call write multiple times.
    let elements = Array(1...200)
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    var writer = UniqueArrayAsyncWriter(capacity: 256)

    try await reader.pipe(into: &writer)

    #expect(writer.storage.count == elements.count)
    for i in 0..<elements.count {
      #expect(writer.storage[i] == elements[i])
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writerIntoRemainsUsableAfterPipe() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 3, copying: [1, 2, 3])
    )
    var writer = UniqueArrayAsyncWriter()

    try await reader.pipe(into: &writer)

    try! await writer.write { buffer in
      buffer.append(99)
    }

    #expect(writer.storage.count == 4)
    #expect(writer.storage[3] == 99)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeBufferingIntoCopiesAllElements() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    var writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(bufferingInto: &writer, intermediateCapacity: 16)

    #expect(writer.storage.count == 5)
    #expect(writer.storage[0] == 1)
    #expect(writer.storage[1] == 2)
    #expect(writer.storage[2] == 3)
    #expect(writer.storage[3] == 4)
    #expect(writer.storage[4] == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeBufferingIntoWithEmptyReader() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray<Int>()
    )
    var writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(bufferingInto: &writer, intermediateCapacity: 16)

    #expect(writer.storage.count == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipeBufferingIntoReusesIntermediateBufferAcrossMultipleIterations() async throws {
    // The intermediate buffer holds 16 elements. With 100 source elements, the loop
    // must iterate at least 7 times, reusing the same buffer.
    let elements = Array(1...100)
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    var writer = UniqueArrayCallerAsyncWriter(capacity: elements.count)

    try await reader.pipe(bufferingInto: &writer, intermediateCapacity: 16)

    #expect(writer.storage.count == elements.count)
    for i in 0..<elements.count {
      #expect(writer.storage[i] == elements[i])
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writerBufferingIntoRemainsUsableAfterPipe() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 3, copying: [1, 2, 3])
    )
    var writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(bufferingInto: &writer, intermediateCapacity: 8)

    var more = UniqueArray(capacity: 1, copying: [99])
    await writer.write(buffer: &more)

    #expect(writer.storage.count == 4)
    #expect(writer.storage[3] == 99)
  }
}
#endif

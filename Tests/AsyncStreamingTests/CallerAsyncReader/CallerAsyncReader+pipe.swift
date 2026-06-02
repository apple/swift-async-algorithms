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
  func pipeIntoCopiesAllElements() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    let writer = UniqueArrayAsyncWriter()

    try await reader.pipe(into: writer)
  }

  @Test
  func pipeIntoWithEmptyReader() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray<Int>()
    )
    let writer = UniqueArrayAsyncWriter()

    try await reader.pipe(into: writer)
  }

  @Test
  func pipeIntoLoopsAcrossMultipleBuffers() async throws {
    let elements = Array(1...200)
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    let writer = UniqueArrayAsyncWriter(capacity: 256)

    try await reader.pipe(into: writer)
  }

  @Test
  func pipeBufferingIntoCopiesAllElements() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    let writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(bufferingInto: writer, intermediateCapacity: 16)
  }

  @Test
  func pipeBufferingIntoWithEmptyReader() async throws {
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray<Int>()
    )
    let writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(bufferingInto: writer, intermediateCapacity: 16)
  }

  @Test
  func pipeBufferingIntoReusesIntermediateBufferAcrossMultipleIterations() async throws {
    let elements = Array(1...100)
    let reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    let writer = UniqueArrayCallerAsyncWriter(capacity: elements.count)

    try await reader.pipe(bufferingInto: writer, intermediateCapacity: 16)
  }
}
#endif

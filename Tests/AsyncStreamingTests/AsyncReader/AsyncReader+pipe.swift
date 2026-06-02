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
  func pipeIntoCopiesAllElements() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    let writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(into: writer)
  }

  @Test
  func pipeIntoWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray<Int>()
    )
    let writer = UniqueArrayCallerAsyncWriter()

    try await reader.pipe(into: writer)
  }

  @Test
  func pipeIntoPreservesElementOrder() async throws {
    let elements = Array(1...50)
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    let writer = UniqueArrayCallerAsyncWriter(capacity: elements.count)

    try await reader.pipe(into: writer)
  }

  @Test
  func pipeCopyingIntoCopiesAllElements() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    let writer = UniqueArrayAsyncWriter()

    try await reader.pipe(copyingInto: writer)
  }

  @Test
  func pipeCopyingIntoWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray<Int>()
    )
    let writer = UniqueArrayAsyncWriter()

    try await reader.pipe(copyingInto: writer)
  }

  @Test
  func pipeCopyingIntoChunksTerminalChunkAcrossMultipleWrites() async throws {
    // The reader's terminal chunk is 200 elements; the writer hands out
    // 64-element buffers. Verify pipe runs without dropping bytes — the
    // payload-bearing version of this scenario in FinalElementPipeTests
    // checks the actual contents delivered.
    let elements = Array(1...200)
    let reader = UniqueArrayAsyncReader(
      storage: UniqueArray(capacity: elements.count, copying: elements)
    )
    let writer = UniqueArrayAsyncWriter(capacity: 256)

    try await reader.pipe(copyingInto: writer)
  }
}
#endif

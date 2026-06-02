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
struct CallerAsyncReaderTests {
  @Test
  func readIntoBuffer() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    var buffer = UniqueArray<Int>(minimumCapacity: 10)

    await reader.read(into: &buffer)

    #expect(buffer.count == 5)
    #expect(buffer[0] == 1)
    #expect(buffer[1] == 2)
    #expect(buffer[2] == 3)
    #expect(buffer[3] == 4)
    #expect(buffer[4] == 5)
  }

  @Test
  func readIntoBufferAtEnd() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 0, copying: [])
    )
    var buffer = UniqueArray<Int>(minimumCapacity: 10)

    await reader.read(into: &buffer)

    #expect(buffer.count == 0)
  }

  @Test
  func readIntoBufferRespectsCapacity() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 10, copying: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    )
    var buffer = UniqueArray<Int>(minimumCapacity: 3)

    await reader.read(into: &buffer)

    #expect(buffer.count == 3)
    #expect(buffer[0] == 1)
    #expect(buffer[1] == 2)
    #expect(buffer[2] == 3)
  }

  @Test
  func readMultipleTimes() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 6, copying: [1, 2, 3, 4, 5, 6])
    )

    var buffer1 = UniqueArray<Int>(minimumCapacity: 3)
    await reader.read(into: &buffer1)
    #expect(buffer1.count == 3)
    #expect(buffer1[0] == 1)
    #expect(buffer1[1] == 2)
    #expect(buffer1[2] == 3)

    var buffer2 = UniqueArray<Int>(minimumCapacity: 3)
    await reader.read(into: &buffer2)
    #expect(buffer2.count == 3)
    #expect(buffer2[0] == 4)
    #expect(buffer2[1] == 5)
    #expect(buffer2[2] == 6)
  }
}
#endif

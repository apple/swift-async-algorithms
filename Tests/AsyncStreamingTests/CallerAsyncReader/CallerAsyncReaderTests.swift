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
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readIntoBuffer() async {
    var reader = UniqueArrayCallerAsyncReader(values: [1, 2, 3, 4, 5])
    var buffer = UniqueArray<NoncopyableInt>(minimumCapacity: 10)

    await reader.read(into: &buffer)

    #expect(buffer.count == 5)
    #expect(buffer[0].value == 1)
    #expect(buffer[1].value == 2)
    #expect(buffer[2].value == 3)
    #expect(buffer[3].value == 4)
    #expect(buffer[4].value == 5)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readIntoBufferAtEnd() async {
    var reader = UniqueArrayCallerAsyncReader(values: [])
    var buffer = UniqueArray<NoncopyableInt>(minimumCapacity: 10)

    await reader.read(into: &buffer)

    #expect(buffer.count == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readIntoBufferRespectsCapacity() async {
    var reader = UniqueArrayCallerAsyncReader(values: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    var buffer = UniqueArray<NoncopyableInt>(minimumCapacity: 3)

    await reader.read(into: &buffer)

    #expect(buffer.count == 3)
    #expect(buffer[0].value == 1)
    #expect(buffer[1].value == 2)
    #expect(buffer[2].value == 3)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readMultipleTimes() async {
    var reader = UniqueArrayCallerAsyncReader(values: [1, 2, 3, 4, 5, 6])

    var buffer1 = UniqueArray<NoncopyableInt>(minimumCapacity: 3)
    await reader.read(into: &buffer1)
    #expect(buffer1.count == 3)
    #expect(buffer1[0].value == 1)
    #expect(buffer1[1].value == 2)
    #expect(buffer1[2].value == 3)

    var buffer2 = UniqueArray<NoncopyableInt>(minimumCapacity: 3)
    await reader.read(into: &buffer2)
    #expect(buffer2.count == 3)
    #expect(buffer2[0].value == 4)
    #expect(buffer2[1].value == 5)
    #expect(buffer2[2].value == 6)
  }
}
#endif

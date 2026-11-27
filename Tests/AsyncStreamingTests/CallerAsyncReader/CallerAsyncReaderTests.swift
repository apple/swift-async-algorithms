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
struct CallerAsyncReaderTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readIntoBuffer() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])
    )
    let bufferStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 10)
    defer { bufferStorage.deallocate() }
    var buffer = OutputSpan(buffer: bufferStorage, initializedCount: 0)
    _ = await reader.read(into: &buffer)

    #expect(buffer.count == 5)
    #expect(buffer.span[0] == 1)
    #expect(buffer.span[1] == 2)
    #expect(buffer.span[2] == 3)
    #expect(buffer.span[3] == 4)
    #expect(buffer.span[4] == 5)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func readIntoBufferAtEnd() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 0, copying: [])
    )
    let bufferStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 10)
    defer { bufferStorage.deallocate() }
    var buffer = OutputSpan(buffer: bufferStorage, initializedCount: 0)
    _ = await reader.read(into: &buffer)

    #expect(buffer.count == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func readIntoBufferRespectsCapacity() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 10, copying: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    )
    let bufferStorage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 3)
    defer { bufferStorage.deallocate() }
    var buffer = OutputSpan(buffer: bufferStorage, initializedCount: 0)
    _ = await reader.read(into: &buffer)

    #expect(buffer.count == 3)
    #expect(buffer.span[0] == 1)
    #expect(buffer.span[1] == 2)
    #expect(buffer.span[2] == 3)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func readMultipleTimes() async {
    var reader = UniqueArrayCallerAsyncReader(
      storage: UniqueArray(capacity: 6, copying: [1, 2, 3, 4, 5, 6])
    )

    let buffer1Storage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 3)

    defer { buffer1Storage.deallocate() }

    var buffer1 = OutputSpan(buffer: buffer1Storage, initializedCount: 0)
    _ = await reader.read(into: &buffer1)
    #expect(buffer1.count == 3)
    #expect(buffer1.span[0] == 1)
    #expect(buffer1.span[1] == 2)
    #expect(buffer1.span[2] == 3)

    let buffer2Storage = UnsafeMutableBufferPointer<Int>.allocate(capacity: 3)

    defer { buffer2Storage.deallocate() }

    var buffer2 = OutputSpan(buffer: buffer2Storage, initializedCount: 0)
    _ = await reader.read(into: &buffer2)
    #expect(buffer2.count == 3)
    #expect(buffer2.span[0] == 4)
    #expect(buffer2.span[1] == 5)
    #expect(buffer2.span[2] == 6)
  }
}
#endif

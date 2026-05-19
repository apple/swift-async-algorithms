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
struct CallerAsyncWriterTests {
  @Test
  func writeBuffer() async {
    var writer = UniqueArrayCallerAsyncWriter()
    var data = UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5])

    await writer.write(buffer: &data)

    #expect(writer.storage.count == 5)
  }

  @Test
  func writeEmptyBuffer() async {
    var writer = UniqueArrayCallerAsyncWriter()
    var data = UniqueArray<Int>()

    await writer.write(buffer: &data)

    #expect(writer.storage.count == 0)
  }

  @Test
  func writeLargeBuffer() async {
    var writer = UniqueArrayCallerAsyncWriter(capacity: 100)
    var data = UniqueArray(capacity: 5, copying: Array(1...50))

    await writer.write(buffer: &data)

    #expect(writer.storage.count == 50)
  }
}
#endif

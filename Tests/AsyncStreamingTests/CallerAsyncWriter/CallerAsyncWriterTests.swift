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
struct CallerAsyncWriterTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeBuffer() async {
    var writer = UniqueArrayCallerAsyncWriter()
    let data = [1, 2, 3, 4, 5]

    await writer.write(data.span)

    #expect(writer.storage.count == 5)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func writeEmptyBuffer() async {
    var writer = UniqueArrayCallerAsyncWriter()
    let data: [Int] = []

    await writer.write(data.span)

    #expect(writer.storage.count == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func writeLargeBuffer() async {
    var writer = UniqueArrayCallerAsyncWriter(capacity: 100)
    let data = Array(1...50)

    await writer.write(data.span)

    #expect(writer.storage.count == 50)
  }
}
#endif

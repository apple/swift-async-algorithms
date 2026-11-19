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
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeBuffer() async {
    let tracker = LifetimeTracker()
    do {
      var writer = UniqueArrayCallerAsyncWriter()
      var data = UniqueArray(values: [1, 2, 3, 4, 5], tracker: tracker)

      await writer.write(buffer: &data)

      #expect(writer.storage.count == 5)
      #expect(writer.storage.values == [1, 2, 3, 4, 5])
      #expect(data.count == 0)
    }
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeEmptyBuffer() async {
    var writer = UniqueArrayCallerAsyncWriter()
    var data = UniqueArray<NoncopyableInt>()

    await writer.write(buffer: &data)

    #expect(writer.storage.count == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeLargeBuffer() async {
    let tracker = LifetimeTracker()
    do {
      var writer = UniqueArrayCallerAsyncWriter(capacity: 100)
      var data = UniqueArray(values: Array(1...50), tracker: tracker)

      await writer.write(buffer: &data)

      #expect(writer.storage.count == 50)
      #expect(writer.storage.values == Array(1...50))
    }
    #expect(tracker.created == 50)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func callerAsyncWriterFinish() async {
    let sink = WriteSink<Void>()

    await UniqueArrayCallerAsyncWriter(sink: sink).finish()

    #expect(sink.values.isEmpty)
    #expect(sink.finished)
  }
}
#endif

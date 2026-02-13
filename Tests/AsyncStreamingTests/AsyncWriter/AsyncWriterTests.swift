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
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeSpan() async {
    var writer = UniqueArrayCallerAsyncWriter()
    var data = UniqueArray<Int>()
    for i in 1...5 {
      data.append(i)
    }

    var consumer = data.consumeAll()
    try! await writer.write(span: consumer.drainNext())

    #expect(writer.storage.count == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeEmptySpan() async {
    var writer = UniqueArrayCallerAsyncWriter()

    try! await writer.write(span: InputSpan<Int>())

    #expect(writer.storage.count == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeLargeSpan() async {
    var writer = UniqueArrayCallerAsyncWriter(capacity: 100)
    var data = UniqueArray<Int>()
    for i in 1...50 {
      data.append(i)
    }

    var consumer = data.consumeAll()
    try! await writer.write(span: consumer.drainNext())

    #expect(writer.storage.count == 50)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeSpanExceedingCapacity() async {
    var writer = UniqueArrayCallerAsyncWriter(capacity: 5)
    var data = UniqueArray<Int>()
    for i in 1...10 {
      data.append(i)
    }

    var consumer = data.consumeAll()
    do {
      try await writer.write(span: consumer.drainNext())
      Issue.record("Expected WriterCapacityError")
    } catch {
      // Expected WriterCapacityError
    }
  }
}
#endif

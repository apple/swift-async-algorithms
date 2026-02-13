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
import _AsyncStreaming
import BasicContainers
import ContainersPreview
import Testing

@Suite
struct CallerAsyncWriterTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeSpan() async {
    var writer = UniqueArrayCallerAsyncWriter()
    let data = [1, 2, 3, 4, 5]

    let buffer = UnsafeMutableBufferPointer<Int>.allocate(capacity: data.count)
    _ = buffer.initialize(from: data)
    var span = InputSpan(buffer: buffer, initializedCount: data.count)
    try! await writer.write(span: span)
    _ = consume span
    buffer.deallocate()

    #expect(writer.elements == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeEmptySpan() async {
    var writer = UniqueArrayCallerAsyncWriter()

    try! await writer.write(span: InputSpan<Int>())

    #expect(writer.elements == [])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeLargeSpan() async {
    var writer = UniqueArrayCallerAsyncWriter(capacity: 100)
    let data = Array(1...50)

    let buffer = UnsafeMutableBufferPointer<Int>.allocate(capacity: data.count)
    _ = buffer.initialize(from: data)
    var span = InputSpan(buffer: buffer, initializedCount: data.count)
    try! await writer.write(span: span)
    _ = consume span
    buffer.deallocate()

    #expect(writer.elements == data)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeSpanExceedingCapacity() async {
    var writer = UniqueArrayCallerAsyncWriter(capacity: 5)
    let data = Array(1...10)

    let buffer = UnsafeMutableBufferPointer<Int>.allocate(capacity: data.count)
    _ = buffer.initialize(from: data)
    var span = InputSpan(buffer: buffer, initializedCount: data.count)
    do {
      try await writer.write(span: span)
      Issue.record("Expected WriterCapacityError")
    } catch {
      // Expected WriterCapacityError
    }
    _ = consume span
    buffer.deallocate()
  }
}
#endif

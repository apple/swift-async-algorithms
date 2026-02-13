//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming
import _AsyncStreaming
import BasicContainers
import Testing

@Suite
struct AsyncWriterTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeElement() async {
    var writer = TestWriter()

    await writer.write(42)

    #expect(writer.storage == [42])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeMultipleElements() async {
    var writer = TestWriter()

    await writer.write(1)
    await writer.write(2)
    await writer.write(3)

    #expect(writer.storage == [1, 2, 3])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeWithOutputSpan() async {
    var writer = TestWriter()

    try! await writer.write { outputSpan in
      outputSpan.append(10)
      outputSpan.append(20)
      outputSpan.append(30)
    }

    #expect(writer.storage == [10, 20, 30])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeSpan() async {
    var writer = TestWriter()
    let data = [1, 2, 3, 4, 5]

    try! await writer.write(data.span)

    #expect(writer.storage == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeEmptySpan() async {
    var writer = TestWriter()
    let data: [Int] = []

    try! await writer.write(data.span)

    #expect(writer.storage == [])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeLargeSpan() async {
    var writer = TestWriter(capacity: 100)
    let data = Array(1...50)

    try! await writer.write(data.span)

    #expect(writer.storage == data)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeSpanExceedingCapacity() async {
    var writer = TestWriter(capacity: 5)
    let data = Array(1...10)

    do {
      try await writer.write(data.span)
      Issue.record("Expected AsyncWriterWroteShortError")
    } catch {
      switch error {
      case .first:
        Issue.record("Expected second error variant")
      case .second:
        break
      }
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func multipleWrites() async {
    var writer = TestWriter()

    try! await writer.write { outputSpan in
      outputSpan.append(1)
      outputSpan.append(2)
    }

    try! await writer.write { outputSpan in
      outputSpan.append(3)
      outputSpan.append(4)
    }

    #expect(writer.storage == [1, 2, 3, 4])
  }
}
#endif

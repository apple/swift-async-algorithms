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
struct AsyncWriterTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeElements() async {
    var writer = UniqueArrayAsyncWriter()

    try! await writer.write { buffer in
      buffer.append(1)
      buffer.append(2)
      buffer.append(3)
    }

    #expect(writer.storage.count == 3)
    #expect(writer.storage[0] == 1)
    #expect(writer.storage[1] == 2)
    #expect(writer.storage[2] == 3)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeEmptyBuffer() async {
    var writer = UniqueArrayAsyncWriter()

    try! await writer.write { _ in }

    #expect(writer.storage.count == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeReturnsValue() async {
    var writer = UniqueArrayAsyncWriter()

    let count = try! await writer.write { buffer in
      buffer.append(10)
      buffer.append(20)
      return buffer.count
    }

    #expect(count == 2)
    #expect(writer.storage.count == 2)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeWithThrowingBody() async {
    enum TestError: Error, Equatable {
      case failed
    }

    var writer = UniqueArrayAsyncWriter()

    do {
      try await writer.write { (_) throws(TestError) -> Void in
        throw TestError.failed
      }
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(error == EitherError<Never, TestError>.second(TestError.failed))
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeMultipleTimes() async {
    var writer = UniqueArrayAsyncWriter()

    try! await writer.write { buffer in
      buffer.append(1)
      buffer.append(2)
    }

    try! await writer.write { buffer in
      buffer.append(3)
      buffer.append(4)
    }

    #expect(writer.storage.count == 4)
    #expect(writer.storage[0] == 1)
    #expect(writer.storage[1] == 2)
    #expect(writer.storage[2] == 3)
    #expect(writer.storage[3] == 4)
  }
}
#endif

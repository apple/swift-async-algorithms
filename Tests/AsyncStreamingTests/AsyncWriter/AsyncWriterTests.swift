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
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeElements() async {
    let tracker = LifetimeTracker()
    do {
      var writer = UniqueArrayAsyncWriter()

      try! await writer.write { buffer in
        buffer.append(NoncopyableInt(1, tracker: tracker))
        buffer.append(NoncopyableInt(2, tracker: tracker))
        buffer.append(NoncopyableInt(3, tracker: tracker))
      }

      #expect(writer.storage.count == 3)
      #expect(writer.storage[0].value == 1)
      #expect(writer.storage[1].value == 2)
      #expect(writer.storage[2].value == 3)
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeEmptyBuffer() async {
    var writer = UniqueArrayAsyncWriter()

    try! await writer.write { _ in }

    #expect(writer.storage.count == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeReturnsValue() async {
    let tracker = LifetimeTracker()
    do {
      var writer = UniqueArrayAsyncWriter()

      let count = try! await writer.write { buffer in
        buffer.append(NoncopyableInt(10, tracker: tracker))
        buffer.append(NoncopyableInt(20, tracker: tracker))
        return buffer.count
      }

      #expect(count == 2)
      #expect(writer.storage.count == 2)
    }
    #expect(tracker.created == 2)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
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

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func writeMultipleTimes() async {
    let tracker = LifetimeTracker()
    do {
      var writer = UniqueArrayAsyncWriter()

      try! await writer.write { buffer in
        buffer.append(NoncopyableInt(1, tracker: tracker))
        buffer.append(NoncopyableInt(2, tracker: tracker))
      }

      try! await writer.write { buffer in
        buffer.append(NoncopyableInt(3, tracker: tracker))
        buffer.append(NoncopyableInt(4, tracker: tracker))
      }

      #expect(writer.storage.count == 4)
      #expect(writer.storage[0].value == 1)
      #expect(writer.storage[1].value == 2)
      #expect(writer.storage[2].value == 3)
      #expect(writer.storage[3].value == 4)
    }
    #expect(tracker.created == 4)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishVoidConvenience() async {
    let writer = UniqueArrayAsyncWriter()
    let sink = writer.sink

    await writer.finish()

    #expect(sink.values.isEmpty)
    #expect(sink.finished)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func finishDeliversFinalElement() async {
    let writer = UniqueArrayAsyncWriter()
    let sink = writer.sink

    await writer.finish(finalElement: ())

    #expect(sink.finished)
    #expect(sink.finalElement != nil)
  }
}
#endif

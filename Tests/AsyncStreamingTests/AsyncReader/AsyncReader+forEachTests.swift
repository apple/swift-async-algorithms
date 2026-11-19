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
struct AsyncReaderforEachBufferTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferIteratesAllSpans() async throws {
    let reader = UniqueArrayAsyncReader(values: [1, 2, 3, 4, 5])
    var elementCount = 0

    await reader.forEachBuffer { buffer in
      elementCount += buffer.count
    }

    #expect(elementCount == 5)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferProcessesElements() async throws {
    let tracker = LifetimeTracker()
    let reader = UniqueArrayAsyncReader(values: [10, 20, 30], tracker: tracker)
    var sum = 0

    await reader.forEachBuffer { buffer in
      for index in buffer.indices {
        sum += buffer[index].value
      }
    }

    #expect(sum == 60)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(values: [])
    var callCount = 0

    await reader.forEachBuffer { buffer in
      callCount += 1
    }

    // The reader signals end-of-stream with an empty buffer; body should not be called.
    #expect(callCount == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferDoesNotInvokeBodyWithEmptyTerminalBuffer() async throws {
    let reader = UniqueArrayAsyncReader(values: [])
    var observedCounts: [Int] = []

    _ = await reader.forEachBuffer { buffer in
      observedCounts.append(buffer.count)
    }

    #expect(observedCounts.allSatisfy { $0 > 0 })
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferThrowingDoesNotInvokeBodyWithEmptyTerminalBuffer() async throws {
    enum TestError: Error {}

    let reader = UniqueArrayAsyncReader(values: [])
    var observedCounts: [Int] = []

    _ = try await reader.forEachBuffer { (buffer) throws(TestError) -> Void in
      observedCounts.append(buffer.count)
    }

    #expect(observedCounts.allSatisfy { $0 > 0 })
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferWithThrowingBody() async {
    enum TestError: Error {
      case failed
    }

    let tracker = LifetimeTracker()
    let reader = UniqueArrayAsyncReader(values: [1, 2, 3], tracker: tracker)

    do {
      _ = try await reader.forEachBuffer { (_) throws(TestError) -> Void in
        throw TestError.failed
      }
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(error == EitherError.second(TestError.failed))
    }

    // The elements the body left in the buffer are freed when it throws.
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferWithNeverFailingReader() async {
    enum TestError: Error {
      case failed
    }

    let reader = UniqueArrayAsyncReader(values: [1, 2, 3])
    var count = 0

    do {
      _ = try await reader.forEachBuffer { (buffer) throws(TestError) -> Void in
        count += buffer.count
      }
    } catch {
      Issue.record("No error should be thrown from reader")
    }

    #expect(count == 3)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBufferWithAsyncWork() async throws {
    let reader = UniqueArrayAsyncReader(values: [1, 2, 3])
    var results: [Int] = []

    _ = await reader.forEachBuffer { buffer in
      await Task.yield()
      for index in buffer.indices {
        results.append(buffer[index].value)
      }
    }

    #expect(results == [1, 2, 3])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBuffer() async throws {
    let tracker = LifetimeTracker()
    let reader = UniqueArrayAsyncReader(chunks: [[1, 2], [3]], tracker: tracker)
    var values: [Int] = []

    await reader.forEachBuffer { (buffer: inout UniqueArray<NoncopyableInt>) async -> Void in
      values += [Int](drainingValues: &buffer)
    }

    #expect(values == [1, 2, 3])
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func throwingForEachBufferFreesElementsWhenBodyThrows() async throws {
    struct StopError: Error, Equatable {}

    let tracker = LifetimeTracker()
    let reader = UniqueArrayAsyncReader(chunks: [[1, 2], [3]], tracker: tracker)
    var values: [Int] = []

    do {
      _ = try await reader.forEachBuffer {
        (buffer: inout UniqueArray<NoncopyableInt>) async throws(StopError) -> Void in
        values += [Int](drainingValues: &buffer)
        throw StopError()
      }
      Issue.record("Expected error")
    } catch {
      #expect(error == .second(StopError()))
    }

    // The body throws on the first chunk, so the second is never read.
    #expect(values == [1, 2])
    #expect(tracker.created == 2)
    #expect(tracker.live == 0)
  }
}

#endif

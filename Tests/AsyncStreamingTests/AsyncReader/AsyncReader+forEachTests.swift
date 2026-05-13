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
struct AsyncReaderforEachChunkTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachChunkIteratesAllSpans() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var elementCount = 0

    await reader.forEachChunk { span in
      elementCount += span.count
    }

    #expect(elementCount == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachChunkProcessesElements() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [10, 20, 30]))
    var sum = 0

    await reader.forEachChunk { span in
      for i in span.indices {
        sum += span[i]
      }
    }

    #expect(sum == 60)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachChunkWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var callCount = 0

    await reader.forEachChunk { span in
      callCount += 1
    }

    #expect(callCount == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachChunkWithThrowingBody() async {
    enum TestError: Error {
      case failed
    }

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    do {
      try await reader.forEachChunk { (span) throws(TestError) -> Void in
        throw TestError.failed
      }
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(error == EitherError.second(TestError.failed))
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachChunkWithNeverFailingReader() async {
    enum TestError: Error {
      case failed
    }

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var count = 0

    do {
      try await reader.forEachChunk { (span) throws(TestError) -> Void in
        count += span.count
      }
    } catch {
      Issue.record("No error should be thrown from reader")
    }

    #expect(count == 3)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachChunkWithAsyncWork() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var results: [Int] = []

    await reader.forEachChunk { span in
      await Task.yield()
      for i in span.indices {
        results.append(span[i])
      }
    }

    #expect(results == [1, 2, 3])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachChunkMultipleSpans() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 6, copying: [1, 2, 3, 4, 5, 6]))
    var spanCounts: [Int] = []

    // Force reading in smaller chunks
    while true {
      let hasMore = try! await reader.read(maximumCount: 2) { span in
        if span.count > 0 {
          spanCounts.append(span.count)
          return true
        }
        return false
      }
      if !hasMore {
        break
      }
    }

    #expect(spanCounts == [2, 2, 2])
  }
}

#endif

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
import Testing

@Suite
struct AsyncReaderForEachTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachIteratesAllSpans() async throws {
    let reader = [1, 2, 3, 4, 5].asyncReader()
    var elementCount = 0

    await reader.forEach { span in
      elementCount += span.count
    }

    #expect(elementCount == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachProcessesElements() async throws {
    let reader = [10, 20, 30].asyncReader()
    var sum = 0

    await reader.forEach { span in
      for i in span.indices {
        sum += span[i]
      }
    }

    #expect(sum == 60)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachWithEmptyReader() async throws {
    let reader = [Int]().asyncReader()
    var callCount = 0

    await reader.forEach { span in
      callCount += 1
    }

    #expect(callCount == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachWithThrowingBody() async {
    enum TestError: Error {
      case failed
    }

    let reader = [1, 2, 3].asyncReader()

    do {
      try await reader.forEach { (span) throws(TestError) -> Void in
        throw TestError.failed
      }
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(error == TestError.failed)
    }
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachWithNeverFailingReader() async {
    enum TestError: Error {
      case failed
    }

    let reader = [1, 2, 3].asyncReader()
    var count = 0

    do {
      try await reader.forEach { (span) throws(TestError) -> Void in
        count += span.count
      }
    } catch {
      Issue.record("No error should be thrown from reader")
    }

    #expect(count == 3)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachWithAsyncWork() async throws {
    let reader = [1, 2, 3].asyncReader()
    var results: [Int] = []

    await reader.forEach { span in
      await Task.yield()
      for i in span.indices {
        results.append(span[i])
      }
    }

    #expect(results == [1, 2, 3])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func forEachMultipleSpans() async {
    var reader = [1, 2, 3, 4, 5, 6].asyncReader()
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

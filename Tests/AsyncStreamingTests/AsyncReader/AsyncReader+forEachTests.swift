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
struct AsyncReaderforEachSpanTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachSpanIteratesAllSpans() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var elementCount = 0

    await reader.forEachSpan { elements in
      elementCount += elements.count
    }

    #expect(elementCount == 5)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func forEachSpanProcessesElements() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [10, 20, 30]))
    var sum = 0

    await reader.forEachSpan { elements in
      for i in elements.indices {
        sum += elements[i]
      }
    }

    #expect(sum == 60)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func forEachSpanWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var callCount = 0

    await reader.forEachSpan { elements in
      callCount += 1
    }

    // The reader signals end-of-stream with an empty buffer; body should not be called.
    #expect(callCount == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func forEachSpanDoesNotInvokeBodyWithEmptyTerminalBuffer() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var observedCounts: [Int] = []

    _ = await reader.forEachSpan { elements in
      observedCounts.append(elements.count)
    }

    #expect(observedCounts.allSatisfy { $0 > 0 })
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func forEachSpanThrowingDoesNotInvokeBodyWithEmptyTerminalBuffer() async throws {
    enum TestError: Error {}

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var observedCounts: [Int] = []

    _ = try await reader.forEachSpan { (elements) throws(TestError) -> Void in
      observedCounts.append(elements.count)
    }

    #expect(observedCounts.allSatisfy { $0 > 0 })
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func forEachSpanWithThrowingBody() async {
    enum TestError: Error {
      case failed
    }

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    do {
      _ = try await reader.forEachSpan { (_) throws(TestError) -> Void in
        throw TestError.failed
      }
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(error as? EitherError<Never, TestError> == EitherError.second(TestError.failed))
    }
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func forEachSpanWithNeverFailingReader() async {
    enum TestError: Error {
      case failed
    }

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var count = 0

    do {
      _ = try await reader.forEachSpan { (elements) throws(TestError) -> Void in
        count += elements.count
      }
    } catch {
      Issue.record("No error should be thrown from reader")
    }

    #expect(count == 3)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func forEachSpanWithAsyncWork() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var results: [Int] = []

    _ = await reader.forEachSpan { elements in
      await Task.yield()
      for i in elements.indices {
        results.append(elements[i])
      }
    }

    #expect(results == [1, 2, 3])
  }
}

#endif

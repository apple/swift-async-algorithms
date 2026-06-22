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
  @Test
  func forEachBufferIteratesAllSpans() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var elementCount = 0

    await reader.forEachBuffer { buffer in
      elementCount += buffer.count
    }

    #expect(elementCount == 5)
  }

  @Test
  func forEachBufferProcessesElements() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [10, 20, 30]))
    var sum = 0

    await reader.forEachBuffer { buffer in
      for i in buffer.indices {
        sum += buffer[i]
      }
    }

    #expect(sum == 60)
  }

  @Test
  func forEachBufferWithEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var callCount = 0

    await reader.forEachBuffer { buffer in
      callCount += 1
    }

    // The reader signals end-of-stream with an empty buffer; body should not be called.
    #expect(callCount == 0)
  }

  @Test
  func forEachBufferDoesNotInvokeBodyWithEmptyTerminalBuffer() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var observedCounts: [Int] = []

    _ = await reader.forEachBuffer { buffer in
      observedCounts.append(buffer.count)
    }

    #expect(observedCounts.allSatisfy { $0 > 0 })
  }

  @Test
  func forEachBufferThrowingDoesNotInvokeBodyWithEmptyTerminalBuffer() async throws {
    enum TestError: Error {}

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var observedCounts: [Int] = []

    _ = try await reader.forEachBuffer { (buffer) throws(TestError) -> Void in
      observedCounts.append(buffer.count)
    }

    #expect(observedCounts.allSatisfy { $0 > 0 })
  }

  @Test
  func forEachBufferWithThrowingBody() async {
    enum TestError: Error {
      case failed
    }

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    do {
      _ = try await reader.forEachBuffer { (_) throws(TestError) -> Void in
        throw TestError.failed
      }
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(error == EitherError.second(TestError.failed))
    }
  }

  @Test
  func forEachBufferWithNeverFailingReader() async {
    enum TestError: Error {
      case failed
    }

    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
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

  @Test
  func forEachBufferWithAsyncWork() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var results: [Int] = []

    _ = await reader.forEachBuffer { buffer in
      await Task.yield()
      for i in buffer.indices {
        results.append(buffer[i])
      }
    }

    #expect(results == [1, 2, 3])
  }
}

#endif

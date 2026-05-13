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
struct AsyncReaderCollectTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectAllElements() async throws {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    let result = try await reader.collect(upTo: 10) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectWithExactLimit() async throws {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    let result = try await reader.collect(upTo: 5) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectEmptyReader() async throws {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))

    let result = try await reader.collect(upTo: 10) { span in
      return span.count
    }

    #expect(result == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectProcessesAllElements() async throws {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [10, 20, 30]))

    let result = try await reader.collect(upTo: 10) { span in
      var sum = 0
      for i in span.indices {
        sum += span[i]
      }
      return sum
    }

    #expect(result == 60)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectThrowsLeftOverElements() async throws {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    let expectedError = EitherError<EitherError<Never, AsyncReaderLeftOverElementsError>, Never>.first(
      .second(AsyncReaderLeftOverElementsError())
    )
    await #expect(throws: expectedError) {
      try await reader.collect(upTo: 1) { span in
        return span.count
      }
    }
  }
}

#endif

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
struct AsyncReaderCollectTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectAllElements() async {
    var reader = [1, 2, 3, 4, 5].asyncReader()

    let result = await reader.collect(upTo: 10) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectWithExactLimit() async {
    var reader = [1, 2, 3, 4, 5].asyncReader()

    let result = await reader.collect(upTo: 5) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectEmptyReader() async {
    var reader = [Int]().asyncReader()

    let result = await reader.collect(upTo: 10) { span in
      return span.count
    }

    #expect(result == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectProcessesAllElements() async {
    var reader = [10, 20, 30].asyncReader()

    let result = await reader.collect(upTo: 10) { span in
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
  func collectIntoOutputSpan() async {
    var reader = [1, 2, 3, 4, 5].asyncReader()
    var buffer = RigidArray<Int>.init(capacity: 5)

    await buffer.append(count: 5) { outputSpan in
      await reader.collect(into: &outputSpan)
    }

    #expect(buffer.count == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectWithNeverFailingReader() async {
    var reader = [1, 2, 3].asyncReader()

    // This tests the Never overload
    let result = await reader.collect(upTo: 10) { span in
      return span.count
    }

    #expect(result == 3)
  }
}
#endif

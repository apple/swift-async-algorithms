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
  func collectAllElements() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    let result = await reader.collect(upTo: 10) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectWithExactLimit() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    let result = await reader.collect(upTo: 5) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectEmptyReader() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))

    let result = await reader.collect(upTo: 10) { span in
      return span.count
    }

    #expect(result == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectProcessesAllElements() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [10, 20, 30]))

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
    // TODO: Cannot test this yet since we can't get `InputSpan`s available in async contexts
    //        var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    //        var buffer = RigidArray<Int>.init(capacity: 5)
    //
    //        await buffer.append(count: 5) { outputSpan in
    //            await reader.collect(into: &outputSpan)
    //        }
    //
    //        #expect(buffer.count == 5)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func collectWithNeverFailingReader() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    // This tests the Never overload
    let result = await reader.collect(upTo: 10) { span in
      return span.count
    }

    #expect(result == 3)
  }
}

#endif

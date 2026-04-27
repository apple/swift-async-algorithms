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
import _AsyncStreaming
import BasicContainers
import ContainersPreview
import Testing

@Suite
struct AsyncReaderTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func readWithMaximumCount() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    let result = try! await reader.read(maximumCount: 3) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func readWithoutMaximumCount() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    let result = try! await reader.read(maximumCount: .max) { span in
      return Array(span)
    }

    #expect(result == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func readEmptySpanAtEnd() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    // Read all data
    _ = try! await reader.read { span in
      return Array(span)
    }

    // Next read should return empty span
    let result = try! await reader.read { span in
      return span.count
    }

    #expect(result == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func readMultipleChunks() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 6, copying: [1, 2, 3, 4, 5, 6]))
    var chunks: [[Int]] = []

    while true {
      let chunk = try! await reader.read(maximumCount: 2) { span in
        return Array(span)
      }
      print(chunk)
      if chunk.isEmpty {
        break
      }
      chunks.append(chunk)
    }

    #expect(chunks == [[1, 2], [3, 4], [5, 6]])
  }
}
#endif

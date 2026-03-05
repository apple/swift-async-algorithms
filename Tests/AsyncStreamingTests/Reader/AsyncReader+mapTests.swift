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
#if !canImport(Darwin) || swift(>=6.3)  // Disabled on older compilers on Darwin due to a runtime crash
import _AsyncStreaming
import Testing

@Suite
struct AsyncReaderMapTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func mapTransformsElements() async throws {
    let reader = [1, 2, 3, 4, 5].asyncReader()
    let mappedReader = reader.map { $0 * 2 }

    var results: [Int] = []
    await mappedReader.forEach { span in
      for i in span.indices {
        results.append(span[i])
      }
    }

    #expect(results == [2, 4, 6, 8, 10])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func mapWithTypeConversion() async throws {
    let reader = [1, 2, 3].asyncReader()
    let mappedReader = reader.map { String($0) }

    var results: [String] = []
    await mappedReader.forEach { span in
      for i in span.indices {
        results.append(span[i])
      }
    }

    #expect(results == ["1", "2", "3"])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func mapEmptyReader() async throws {
    let reader = [Int]().asyncReader()
    let mappedReader = reader.map { $0 * 2 }

    var count = 0
    await mappedReader.forEach { span in
      count += span.count
    }

    #expect(count == 0)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func mapWithAsyncTransformation() async throws {
    let reader = [1, 2, 3].asyncReader()
    let mappedReader = reader.map { value in
      // Simulate async work
      await Task.yield()
      return value * 10
    }

    var results: [Int] = []
    await mappedReader.forEach { span in
      for i in span.indices {
        results.append(span[i])
      }
    }

    #expect(results == [10, 20, 30])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func mapPreservesChunking() async {
    let reader = [1, 2, 3, 4, 5, 6].asyncReader()
    var mappedReader = reader.map { $0 + 100 }

    // Read in chunks
    var chunks: [[Int]] = []
    while true {
      let chunk = try! await mappedReader.read(maximumCount: 2) { span in
        return Array(span)
      }
      if chunk.isEmpty {
        break
      }
      chunks.append(chunk)
    }

    #expect(chunks == [[101, 102], [103, 104], [105, 106]])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func mapChaining() async throws {
    let reader = [1, 2, 3].asyncReader()
    let mappedReader =
      reader
      .map { $0 * 2 }
      .map { $0 + 10 }

    var results: [Int] = []
    await mappedReader.forEach { span in
      for i in span.indices {
        results.append(span[i])
      }
    }

    #expect(results == [12, 14, 16])
  }
}
#endif
#endif

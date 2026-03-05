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
struct ArrayAsyncReaderTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func oneSpan() async throws {
    let array = [1, 2, 3].asyncReader()
    var counter = 0
    await array.forEach { span in
      counter += 1
      #expect(span.count == 3)
    }
    #expect(counter == 1)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func multipleSpans() async throws {
    var array = [1, 2, 3].asyncReader()
    var counter = 0
    var continueReading = true
    while continueReading {
      try await array.read(maximumCount: 1) { span in
        guard span.count > 0 else {
          continueReading = false
          return
        }
        counter += 1
        #expect(span.count == 1)
      }
    }
    #expect(counter == 3)
  }
}
#endif

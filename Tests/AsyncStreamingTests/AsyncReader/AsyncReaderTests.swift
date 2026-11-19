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
struct AsyncReaderTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func read() async {
    let tracker = LifetimeTracker()
    do {
      var reader = UniqueArrayAsyncReader(values: [1, 2, 3, 4, 5], tracker: tracker)

      var observedFinal = false
      let result: UniqueArray<NoncopyableInt> = try! await reader.read { (buffer, finalElement) in
        observedFinal = finalElement != nil
        var moved = UniqueArray<NoncopyableInt>()
        moved.append(moving: buffer.startIndex..<buffer.endIndex, from: &buffer)
        return moved
      }

      #expect(result.count == 5)
      #expect(result[0].value == 1)
      #expect(result[1].value == 2)
      #expect(result[2].value == 3)
      #expect(result[3].value == 4)
      #expect(result[4].value == 5)
      #expect(observedFinal)
    }
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readDeliversTerminator() async {
    let tracker = LifetimeTracker()
    var reader = UniqueArrayAsyncReader(values: [1, 2, 3], tracker: tracker)

    var observedFinal = false
    let count: Int = try! await reader.read { (buffer, finalElement) in
      observedFinal = finalElement != nil
      return buffer.count
    }

    #expect(count == 3)
    #expect(observedFinal)
    // The elements left in the buffer are freed when the read returns.
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}
#endif

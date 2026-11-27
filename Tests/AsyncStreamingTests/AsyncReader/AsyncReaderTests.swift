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
struct AsyncReaderTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func read() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    var observedFinal = false
    let result: [Int] = try! await reader.read { (elements, finalElement) in
      observedFinal = finalElement != nil
      return Array(elements)
    }

    #expect(result.count == 5)
    #expect(result[0] == 1)
    #expect(result[1] == 2)
    #expect(result[2] == 3)
    #expect(result[3] == 4)
    #expect(result[4] == 5)
    #expect(observedFinal)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)

  @Test
  func readDeliversTerminator() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    var observedFinal = false
    let count: Int = try! await reader.read { (elements, finalElement) in
      observedFinal = finalElement != nil
      return elements.count
    }

    #expect(count == 3)
    #expect(observedFinal)
  }
}
#endif

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
  @Test
  func read() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))

    var observedFinal = false
    let result: UniqueArray<Int> = try! await reader.read { (buffer, finalElement) in
      observedFinal = finalElement != nil
      return buffer.clone()
    }

    #expect(result.count == 5)
    #expect(result[0] == 1)
    #expect(result[1] == 2)
    #expect(result[2] == 3)
    #expect(result[3] == 4)
    #expect(result[4] == 5)
    #expect(observedFinal)
  }

  @Test
  func readDeliversTerminator() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    var observedFinal = false
    let count: Int = try! await reader.read { (buffer, finalElement) in
      observedFinal = finalElement != nil
      return buffer.count
    }

    #expect(count == 3)
    #expect(observedFinal)
  }
}
#endif

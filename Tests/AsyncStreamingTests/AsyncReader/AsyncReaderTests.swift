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

    let result = try! await reader.read { buffer in
      return buffer.clone()
    }

    #expect(result.count == 5)
    #expect(result[0] == 1)
    #expect(result[1] == 2)
    #expect(result[2] == 3)
    #expect(result[3] == 4)
    #expect(result[4] == 5)
  }

  @Test
  func readEmptyAtEnd() async {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))

    // Read all data
    let first = try! await reader.read { buffer in
      return buffer.count
    }

    #expect(first == 3)

    // Next read should return empty span
    let second = try! await reader.read { buffer in
      return buffer.count
    }

    #expect(second == 0)
  }
}
#endif

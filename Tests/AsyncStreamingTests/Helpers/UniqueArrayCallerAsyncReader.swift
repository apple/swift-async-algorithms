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

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, visionOS 1.0, *)
struct UniqueArrayCallerAsyncReader: ~Copyable, CallerAsyncReader {
  typealias ReadElement = Int
  typealias ReadFailure = Never

  var storage: UniqueArray<Int>
  var position: Int = 0

  mutating func read(
    into buffer: inout OutputSpan<Int>
  ) async throws(Never) {
    guard position < storage.count else { return }
    let count = min(buffer.freeCapacity, storage.count - position)
    for i in 0..<count {
      buffer.append(storage[position + i])
    }
    position += count
  }
}
#endif

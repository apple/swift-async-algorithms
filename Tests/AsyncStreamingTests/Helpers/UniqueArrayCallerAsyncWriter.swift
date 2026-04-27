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

struct WriterCapacityError: Error {}

@available(macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2, visionOS 1.0, *)
struct UniqueArrayCallerAsyncWriter: ~Copyable, CallerAsyncWriter {
  typealias WriteElement = Int
  typealias WriteFailure = WriterCapacityError

  var storage: UniqueArray<Int>

  var elements: [Int] { Array(storage.span) }

  init(capacity: Int = 100) {
    self.storage = UniqueArray(capacity: capacity)
  }

  mutating func write(
    span: borrowing InputSpan<Int>
  ) async throws(WriterCapacityError) {
    guard span.count <= storage.freeCapacity else {
      throw WriterCapacityError()
    }
    for i in span.indices {
      storage.append(span[i])
    }
  }
}
#endif

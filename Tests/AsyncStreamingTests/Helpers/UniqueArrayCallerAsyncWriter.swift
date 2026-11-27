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

struct WriterCapacityError: Error {}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct UniqueArrayCallerAsyncWriter: ~Copyable, CallerAsyncWriter {
  typealias WriteElement = Int
  typealias WriteFailure = Never
  typealias FinalElement = Void

  var storage: UniqueArray<Int>
  var didFinish: Bool = false

  init(capacity: Int = 100) {
    self.storage = UniqueArray(minimumCapacity: capacity)
  }

  mutating func write(
    _ elements: Span<Int>
  ) async throws(WriteFailure) {
    self.storage.append(copying: elements)
  }

  consuming func finish(
    _ elements: Span<Int>,
    finalElement: consuming Void
  ) async throws(WriteFailure) {
    self.storage.append(copying: elements)
    self.didFinish = true
  }
}
#endif

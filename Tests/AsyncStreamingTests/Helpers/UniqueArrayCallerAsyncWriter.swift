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

struct WriterCapacityError: Error {}

struct UniqueArrayCallerAsyncWriter: ~Copyable, CallerAsyncWriter {
  typealias WriteElement = Int
  typealias WriteFailure = Never
  typealias FinalElement = Void

  var storage: UniqueArray<Int>
  var didFinish: Bool = false

  init(capacity: Int = 100) {
    self.storage = UniqueArray(minimumCapacity: capacity)
  }

  mutating func write<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer
  ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
    self.storage.reserveCapacity(buffer.count)
    var consumer = buffer.consumeAll()
    while let element = consumer.next() {
      self.storage.append(element)
    }
  }

  consuming func finish<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer,
    finalElement: consuming Void
  ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
    self.storage.reserveCapacity(buffer.count)
    var consumer = buffer.consumeAll()
    while let element = consumer.next() {
      self.storage.append(element)
    }
    self.didFinish = true
  }
}
#endif

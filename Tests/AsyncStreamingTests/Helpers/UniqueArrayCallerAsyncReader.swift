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

struct UniqueArrayCallerAsyncReader: ~Copyable, CallerAsyncReader {
  typealias ReadElement = Int
  typealias ReadFailure = Never
  typealias FinalElement = Void

  var storage: UniqueArray<Int>
  var position: Int = 0
  var didEmitFinal: Bool = false

  mutating func read<Buffer: RangeReplaceableContainer<ReadElement> & ~Copyable>(
    into buffer: inout Buffer
  ) async throws(ReadFailure) -> Void? where Buffer.Element: ~Copyable {
    precondition(!self.didEmitFinal, "read called after end-of-stream")
    let count = min(buffer.freeCapacity, storage.count - position)
    for i in 0..<count {
      buffer.append(storage[position + i])
    }
    position += count
    if position >= storage.count {
      self.didEmitFinal = true
      return .some(())
    }
    return nil
  }
}
#endif

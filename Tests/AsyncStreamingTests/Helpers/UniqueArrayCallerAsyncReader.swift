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

/// A ``CallerAsyncReader`` that fills each caller buffer with as many of
/// `values` as fit, as ``NoncopyableInt`` elements, and returns
/// `finalElement` from the read that delivers the last one. Pass
/// `maximumChunkSize` to cap how many it delivers per read, whatever the
/// buffer's capacity.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct UniqueArrayCallerAsyncReader<FinalElement: ~Copyable>: ~Copyable, CallerAsyncReader {
  typealias ReadElement = NoncopyableInt
  typealias ReadFailure = Never

  let values: [Int]
  let maximumChunkSize: Int
  var position: Int = 0
  var didEmitFinal: Bool = false
  var finalElement: FinalElement?

  init(
    values: [Int],
    finalElement: consuming FinalElement,
    maximumChunkSize: Int = .max
  ) {
    precondition(maximumChunkSize > 0, "maximumChunkSize must be positive")
    self.values = values
    self.maximumChunkSize = maximumChunkSize
    self.finalElement = .some(finalElement)
  }

  mutating func read<Buffer: RangeReplaceableContainer<ReadElement> & ~Copyable>(
    into buffer: inout Buffer
  ) async throws(ReadFailure) -> FinalElement? where Buffer.Element: ~Copyable {
    precondition(!self.didEmitFinal, "read called after end-of-stream")
    let count = min(buffer.freeCapacity, self.maximumChunkSize, self.values.count - self.position)
    for i in 0..<count {
      buffer.append(NoncopyableInt(self.values[self.position + i]))
    }
    self.position += count
    if self.position >= self.values.count {
      self.didEmitFinal = true
      return self.finalElement.take()
    }
    return nil
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension UniqueArrayCallerAsyncReader where FinalElement == Void {
  init(values: [Int], maximumChunkSize: Int = .max) {
    self.init(values: values, finalElement: (), maximumChunkSize: maximumChunkSize)
  }
}
#endif

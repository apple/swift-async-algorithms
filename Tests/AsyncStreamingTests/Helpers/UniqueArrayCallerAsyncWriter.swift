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

/// A ``CallerAsyncWriter`` of ``NoncopyableInt`` elements. It keeps the
/// written elements in `storage` and records their values and the final
/// element in `sink`.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct UniqueArrayCallerAsyncWriter<FinalElement: ~Copyable>: ~Copyable, CallerAsyncWriter {
  typealias WriteElement = NoncopyableInt
  typealias WriteFailure = Never

  var storage: UniqueArray<NoncopyableInt>
  let sink: WriteSink<FinalElement>

  init(capacity: Int = 100, sink: WriteSink<FinalElement>) {
    self.storage = UniqueArray(minimumCapacity: capacity)
    self.sink = sink
  }

  mutating func write<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer
  ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
    self.append(draining: &buffer)
    self.sink.writes += 1
  }

  consuming func finish<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    buffer: inout Buffer,
    finalElement: consuming FinalElement
  ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
    self.append(draining: &buffer)
    self.sink.finished = true
    self.sink.finalElement = .some(finalElement)
  }

  private mutating func append<Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
    draining buffer: inout Buffer
  ) where Buffer.Element: ~Copyable {
    self.storage.reserveCapacity(self.storage.count + buffer.count)
    var consumer = buffer.consumeAll()
    while let element = consumer.next() {
      self.sink.values.append(element.value)
      self.storage.append(element)
    }
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension UniqueArrayCallerAsyncWriter where FinalElement == Void {
  init(capacity: Int = 100) {
    self.init(capacity: capacity, sink: WriteSink())
  }
}
#endif

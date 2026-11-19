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

/// An ``AsyncWriter`` of ``NoncopyableInt`` elements. It keeps the written
/// elements in `storage` and records their values and the final element in
/// `sink`. Each `write` hands its body an empty buffer with room for
/// `bufferCapacity` elements.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct UniqueArrayAsyncWriter<FinalElement: ~Copyable>: ~Copyable, AsyncWriter {
  typealias WriteElement = NoncopyableInt
  typealias Buffer = UniqueArray<NoncopyableInt>
  typealias WriteFailure = Never

  var storage: UniqueArray<NoncopyableInt>
  let sink: WriteSink<FinalElement>
  let bufferCapacity: Int

  init(capacity: Int = 100, bufferCapacity: Int = 64, sink: WriteSink<FinalElement>) {
    self.storage = UniqueArray(minimumCapacity: capacity)
    self.bufferCapacity = bufferCapacity
    self.sink = sink
  }

  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout UniqueArray<NoncopyableInt>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    var buffer = UniqueArray<NoncopyableInt>(minimumCapacity: self.bufferCapacity)
    do {
      let result = try await body(&buffer)
      var consumer = buffer.consumeAll()
      while let element = consumer.next() {
        self.sink.values.append(element.value)
        self.storage.append(element)
      }
      self.sink.writes += 1
      return result
    } catch {
      throw .second(error)
    }
  }

  consuming func finish(
    finalElement: consuming FinalElement
  ) async throws(Never) {
    self.sink.finished = true
    self.sink.finalElement = .some(finalElement)
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension UniqueArrayAsyncWriter where FinalElement == Void {
  init(capacity: Int = 100, bufferCapacity: Int = 64) {
    self.init(capacity: capacity, bufferCapacity: bufferCapacity, sink: WriteSink())
  }
}
#endif

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

/// Records which leases came back, in order.
final class LeasePool: @unchecked Sendable {
  var returned: [Int] = []
}

/// A noncopyable buffer that goes back to its pool when it is destroyed.
struct Lease: ~Copyable {
  let id: Int
  let pool: LeasePool

  deinit {
    self.pool.returned.append(self.id)
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension UniqueArray where Element == Lease {
  init(leases ids: Range<Int>, from pool: LeasePool) {
    self.init(minimumCapacity: ids.count)
    for id in ids {
      self.append(Lease(id: id, pool: pool))
    }
  }

  var ids: [Int] {
    var ids = [Int]()
    for index in self.indices {
      ids.append(self[index].id)
    }
    return ids
  }
}

/// Hands out its leases in chunks of at most `maxCount` and fuses the last
/// chunk with the end of the stream.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct LeaseAsyncReader: ~Copyable, AsyncReader {
  typealias ReadElement = Lease
  typealias ReadFailure = Never

  var storage: UniqueArray<Lease>
  var didEmitFinal = false

  mutating func read<Return: ~Copyable, Failure: Error>(
    maxCount: Int,
    body: (inout InputSpan<Lease>, Void?) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    precondition(!self.didEmitFinal, "read called after end-of-stream")
    let count = min(maxCount, self.storage.count)
    let isLast = count == self.storage.count
    self.didEmitFinal = isLast
    var chunk = UniqueArray<Lease>(minimumCapacity: count)
    self.storage.consumeSubrange(0..<count) { elements in
      chunk.append(addingCount: count) { output in
        output.append(moving: &elements)
      }
    }
    do {
      return try await chunk.consumeAll { (elements: inout InputSpan<Lease>) async throws(Failure) -> Return in
        try await body(&elements, isLast ? .some(()) : nil)
      }
    } catch {
      throw .second(error)
    }
  }
}

/// Takes ownership of the leases written to it and keeps them, like a writer
/// that holds a buffer until the destination is done with it.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct LeaseCallerAsyncWriter: ~Copyable, CallerAsyncWriter {
  typealias WriteElement = Lease
  typealias WriteFailure = Never

  /// The ids of the leases that the writer kept when it finished.
  let finishedIDs: LeasePool
  var kept = UniqueArray<Lease>()
  var borrowedIDs: [Int] = []

  mutating func write(_ elements: Span<Lease>) async {
    for index in elements.indices {
      self.borrowedIDs.append(elements[index].id)
    }
  }

  mutating func write(_ elements: inout InputSpan<Lease>) async {
    let count = elements.count
    self.kept.append(addingCount: count) { output in
      output.append(moving: &elements)
    }
  }

  consuming func finish(_ elements: Span<Lease>, finalElement: consuming Void) async {
    await self.write(elements)
    self.finishedIDs.returned = self.kept.ids
  }

  consuming func finish(_ elements: inout InputSpan<Lease>, finalElement: consuming Void) async {
    await self.write(&elements)
    self.finishedIDs.returned = self.kept.ids
  }
}

/// Lends an output span over its own storage and keeps the leases that the
/// caller moves into it.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct LeaseAsyncWriter: ~Copyable, AsyncWriter {
  typealias WriteElement = Lease
  typealias WriteFailure = Never

  let finishedIDs: LeasePool
  let capacity: Int
  var kept = UniqueArray<Lease>()

  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout OutputSpan<Lease>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    do {
      return try await self.kept.append(addingCount: self.capacity) {
        (output: inout OutputSpan<Lease>) async throws(Failure) -> Return in
        try await body(&output)
      }
    } catch {
      throw .second(error)
    }
  }

  consuming func finish(finalElement: consuming Void) async {
    self.finishedIDs.returned = self.kept.ids
  }
}
#endif

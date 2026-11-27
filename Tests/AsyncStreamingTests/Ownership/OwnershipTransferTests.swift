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
import Testing

@Suite
struct OwnershipTransferTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readLimitsChunksToMaxCount() async throws {
    var reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var chunks: [[Int]] = []
    var isFinished = false
    while !isFinished {
      isFinished = try await reader.read(maxCount: 2) { (elements, final) async throws(Never) -> Bool in
        chunks.append(Array(elements.span))
        return final != nil
      }
    }
    #expect(chunks == [[1, 2], [3, 4], [5]])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func readLetsTheBodyTakeOwnershipAndDestroysTheRest() async throws {
    let pool = LeasePool()
    var reader = LeaseAsyncReader(storage: UniqueArray(leases: 0..<4, from: pool))
    var taken = UniqueArray<Lease>()

    try await reader.read { (elements, _) async throws(Never) -> Void in
      taken.append(elements.removeFirst())
      taken.append(elements.removeFirst())
    }

    #expect(taken.ids == [0, 1])
    #expect(pool.returned == [2, 3])
    taken.removeAll()
    #expect(pool.returned == [2, 3, 0, 1])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeIntoCallerAsyncWriterMovesLeases() async throws {
    let pool = LeasePool()
    let finishedIDs = LeasePool()
    let reader = LeaseAsyncReader(storage: UniqueArray(leases: 0..<5, from: pool))

    try await reader.pipe(into: LeaseCallerAsyncWriter(finishedIDs: finishedIDs))

    #expect(finishedIDs.returned == [0, 1, 2, 3, 4])
    #expect(pool.returned == [0, 1, 2, 3, 4])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func pipeMovingIntoAsyncWriterMovesLeases() async throws {
    let pool = LeasePool()
    let finishedIDs = LeasePool()
    let reader = LeaseAsyncReader(storage: UniqueArray(leases: 0..<5, from: pool))

    try await reader.pipe(movingInto: LeaseAsyncWriter(finishedIDs: finishedIDs, capacity: 2))

    #expect(finishedIDs.returned == [0, 1, 2, 3, 4])
    #expect(pool.returned == [0, 1, 2, 3, 4])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectMovesLeasesIntoTheTarget() async throws {
    let pool = LeasePool()
    let reader = LeaseAsyncReader(storage: UniqueArray(leases: 0..<3, from: pool))
    var target = UniqueArray<Lease>()

    try await reader.collect(into: &target, maximumSize: 3)

    #expect(target.ids == [0, 1, 2])
    #expect(pool.returned.isEmpty)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func defaultConsumingWriteBorrowsAndEmptiesTheSpan() async throws {
    var writer = UniqueArrayCallerAsyncWriter()
    var source = UniqueArray<Int>(capacity: 3, copying: [1, 2, 3])

    await source.consumeAll { (elements: inout InputSpan<Int>) async -> Void in
      await writer.write(&elements)
      let isEmpty = elements.isEmpty
      #expect(isEmpty)
    }

    #expect(Array(writer.storage.span) == [1, 2, 3])
    let sourceIsEmpty = source.isEmpty
    #expect(sourceIsEmpty)
  }
}
#endif

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

private struct TestError: Error {}

@Suite
struct AsyncSpanExtensionsTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func arrayAppendReadsIntoTheFreeCapacity() async throws {
    var reader = UniqueArrayCallerAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var array = [0]

    var final: Void? = nil
    while final == nil {
      final = await array.append(addingCapacity: 2) { (output: inout OutputSpan<Int>) async -> Void? in
        await reader.read(into: &output)
      }
    }

    #expect(array == [0, 1, 2, 3, 4, 5])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func arrayAppendKeepsTheElementsWhenTheInitializerThrows() async throws {
    var array = [0]

    await #expect(throws: TestError.self) {
      try await array.append(addingCapacity: 3) { (output: inout OutputSpan<Int>) async throws(TestError) -> Void in
        output.append(1)
        await Task.yield()
        throw TestError()
      }
    }

    #expect(array == [0, 1])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func arrayConsumeAllHandsTheElementsToAWriterAndKeepsTheCapacity() async throws {
    var writer = UniqueArrayCallerAsyncWriter()
    var array = [1, 2, 3]
    let capacity = array.capacity

    await array.consumeAll { (elements: inout InputSpan<Int>) async -> Void in
      await writer.write(&elements)
    }

    #expect(Array(writer.storage.span) == [1, 2, 3])
    #expect(array.isEmpty)
    #expect(array.capacity == capacity)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func uniqueArrayAppendAndConsumeAllMoveLeases() async throws {
    let pool = LeasePool()
    var reader = LeaseAsyncReader(storage: UniqueArray(leases: 0..<3, from: pool))
    var leases = UniqueArray<Lease>()

    try await reader.read { (elements, _) async throws(Never) -> Void in
      let count = elements.count
      await leases.append(addingCount: count) { (output: inout OutputSpan<Lease>) async -> Void in
        await Task.yield()
        output.append(moving: &elements)
      }
    }
    #expect(leases.ids == [0, 1, 2])
    #expect(pool.returned.isEmpty)

    let finishedIDs = LeasePool()
    var writer = LeaseCallerAsyncWriter(finishedIDs: finishedIDs)
    await leases.consumeAll { (elements: inout InputSpan<Lease>) async -> Void in
      await writer.write(&elements)
    }
    await writer.finish(Span(), finalElement: ())
    #expect(finishedIDs.returned == [0, 1, 2])
    let leasesAreEmpty = leases.isEmpty
    #expect(leasesAreEmpty)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func inlineArrayInitializesFromAReaderAndConsumesIntoAWriter() async throws {
    var reader = UniqueArrayCallerAsyncReader(storage: UniqueArray(capacity: 4, copying: [1, 2, 3, 4]))
    let array = await InlineArray<4, Int> { (output: inout OutputSpan<Int>) async -> Void in
      while !output.isFull {
        _ = await reader.read(into: &output)
      }
    }
    #expect(array[0] == 1 && array[3] == 4)

    var writer = UniqueArrayCallerAsyncWriter()
    await array.consumeAll { (elements: inout InputSpan<Int>) async -> Void in
      await writer.write(&elements)
    }
    #expect(Array(writer.storage.span) == [1, 2, 3, 4])
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func inlineArrayConsumeAllDestroysTheElementsLeftBehind() async throws {
    let pool = LeasePool()
    var nextID = 0
    let array = InlineArray<2, Lease> { _ in
      defer { nextID += 1 }
      return Lease(id: nextID, pool: pool)
    }

    let first = await array.consumeAll { (elements: inout InputSpan<Lease>) async -> Lease in
      elements.removeFirst()
    }

    #expect(first.id == 0)
    #expect(pool.returned == [1])
  }
}
#endif

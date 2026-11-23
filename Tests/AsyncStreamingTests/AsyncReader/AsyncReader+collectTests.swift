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
import Testing

// The tests that take `chunks` run once with all the values in one read and
// once split over two reads, so that `collect` both appends a chunk that is not
// the last one and handles the final element arriving with a later chunk.
// Each test checks that every element it created was freed, on the success and
// the error paths alike.

@Suite
struct AsyncReaderCollectIntoTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectFillsTargetWhenReaderHasFewerElements() async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(values: [1, 2, 3], tracker: tracker)
      var target = RigidArray<NoncopyableInt>(capacity: 10)

      try await reader.collect(into: &target)

      #expect([Int](drainingValues: &target) == [1, 2, 3])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[1, 2, 3]], [[1, 2], [3]]])
  func collectFillsTargetWhenReaderHasExactlyFreeCapacityElements(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = RigidArray<NoncopyableInt>(capacity: 3)

      try await reader.collect(into: &target)

      #expect(target.count == 3)
      #expect(target.values == [1, 2, 3])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[1, 2, 3, 4, 5]], [[1, 2], [3, 4, 5]]])
  func collectThrowsWhenReaderProducesMoreThanFreeCapacity(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = RigidArray<NoncopyableInt>(capacity: 2)

      do {
        try await reader.collect(into: &target)
        Issue.record("Expected error")
      } catch {
        let expected = EitherError<Never, AsyncReaderLeftOverElementsError>.second(AsyncReaderLeftOverElementsError())
        #expect(error == expected)
      }
      // The left-over elements are freed; only the ones in the target remain.
      #expect(tracker.live == target.count)
    }
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectIntoEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(values: [])
    var target = RigidArray<NoncopyableInt>(capacity: 5)

    try await reader.collect(into: &target)

    #expect(target.count == 0)
  }
}

@Suite
struct AsyncReaderCollectExactlyTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[1, 2, 3]], [[1, 2], [3]]])
  func collectExactlyFillsTargetWhenReaderProducesExactCount(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = RigidArray<NoncopyableInt>(capacity: 3)

      try await reader.collect(exactlyInto: &target)

      #expect([Int](drainingValues: &target) == [1, 2, 3])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[1, 2, 3]], [[1, 2], [3]]])
  func collectExactlyThrowsWhenReaderProducesFewer(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = RigidArray<NoncopyableInt>(capacity: 5)

      do {
        try await reader.collect(exactlyInto: &target)
        Issue.record("Expected error")
      } catch {
        let expected = EitherError<
          Never,
          EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>
        >.second(.second(AsyncReaderInsufficientElementsError()))
        #expect(error == expected)
      }
      // The elements of the short final chunk are freed; only the ones in the target remain.
      #expect(tracker.live == target.count)
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[1, 2, 3, 4, 5]], [[1, 2], [3, 4, 5]]])
  func collectExactlyThrowsWhenReaderProducesMore(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = RigidArray<NoncopyableInt>(capacity: 2)

      do {
        try await reader.collect(exactlyInto: &target)
        Issue.record("Expected error")
      } catch {
        let expected = EitherError<
          Never,
          EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>
        >.second(.first(AsyncReaderLeftOverElementsError()))
        #expect(error == expected)
      }
      // The left-over elements are freed; only the ones in the target remain.
      #expect(tracker.live == target.count)
    }
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }
}

@Suite
struct AsyncReaderCollectIntoMaximumSizeTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[1, 2, 3]], [[1, 2], [3]]])
  func collectGrowsContainerWhenReaderHasFewerThanMaximum(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = UniqueArray<NoncopyableInt>()

      try await reader.collect(into: &target, maximumSize: 10)

      #expect([Int](drainingValues: &target) == [1, 2, 3])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[10, 20, 30]], [[10, 20], [30]]])
  func collectFillsContainerExactlyAtMaximum(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = UniqueArray<NoncopyableInt>()

      try await reader.collect(into: &target, maximumSize: 3)

      #expect(target.count == 3)
      #expect(target.values == [10, 20, 30])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [[[1, 2, 3, 4, 5]], [[1, 2], [3, 4, 5]]])
  func collectThrowsWhenReaderProducesMoreThanMaximum(chunks: [[Int]]) async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(chunks: chunks, tracker: tracker)
      var target = UniqueArray<NoncopyableInt>()

      do {
        try await reader.collect(into: &target, maximumSize: 2)
        Issue.record("Expected error")
      } catch {
        let expected = EitherError<Never, AsyncReaderLeftOverElementsError>.second(AsyncReaderLeftOverElementsError())
        #expect(error == expected)
      }
      // The left-over elements are freed; only the ones in the target remain.
      #expect(tracker.live == target.count)
    }
    #expect(tracker.created == 5)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectAppendsToExistingContents() async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(values: [3, 4], tracker: tracker)
      var target = UniqueArray<NoncopyableInt>(values: [1, 2], tracker: tracker)

      try await reader.collect(into: &target, maximumSize: 10)

      #expect([Int](drainingValues: &target) == [1, 2, 3, 4])
    }
    #expect(tracker.created == 4)
    #expect(tracker.live == 0)
  }
}

/// `collect` returns the reader's final element, which may be noncopyable.
@Suite
struct AsyncReaderCollectFinalElementTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectIntoReturnsNoncopyableFinalElement() async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(
        chunks: [[1, 2], [3]],
        finalElement: NoncopyableInt(99, tracker: tracker),
        tracker: tracker
      )
      var target = RigidArray<NoncopyableInt>(capacity: 3)
      let finalElement = try await reader.collect(into: &target)
      let finalValue = finalElement.value
      #expect(finalValue == 99)
      #expect(target.values == [1, 2, 3])
    }
    #expect(tracker.created == 4)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectExactlyIntoReturnsNoncopyableFinalElement() async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(
        chunks: [[1, 2], [3]],
        finalElement: NoncopyableInt(99, tracker: tracker),
        tracker: tracker
      )
      var target = RigidArray<NoncopyableInt>(capacity: 3)
      let finalElement = try await reader.collect(exactlyInto: &target)
      let finalValue = finalElement.value
      #expect(finalValue == 99)
      #expect(target.values == [1, 2, 3])
    }
    #expect(tracker.created == 4)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectIntoMaximumSizeReturnsNoncopyableFinalElement() async throws {
    let tracker = LifetimeTracker()
    do {
      let reader = UniqueArrayAsyncReader(
        chunks: [[1, 2], [3]],
        finalElement: NoncopyableInt(99, tracker: tracker),
        tracker: tracker
      )
      var target = UniqueArray<NoncopyableInt>()
      let finalElement = try await reader.collect(into: &target, maximumSize: 3)
      let finalValue = finalElement.value
      #expect(finalValue == 99)
      #expect(target.values == [1, 2, 3])
    }
    #expect(tracker.created == 4)
    #expect(tracker.live == 0)
  }
}
#endif

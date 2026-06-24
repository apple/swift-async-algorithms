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

@Suite
struct AsyncReaderCollectIntoTests {
  @Test
  func collectFillsTargetWhenReaderHasFewerElements() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var target = RigidArray<Int>(capacity: 10)

    try await reader.collect(into: &target)

    var collected: [Int] = []
    var c = target.consumeAll()
    while let v = c.next() { collected.append(v) }
    #expect(collected == [1, 2, 3])
  }

  @Test
  func collectFillsTargetWhenReaderHasExactlyFreeCapacityElements() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var target = RigidArray<Int>(capacity: 3)

    try await reader.collect(into: &target)

    #expect(target.count == 3)
  }

  @Test
  func collectThrowsWhenReaderProducesMoreThanFreeCapacity() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var target = RigidArray<Int>(capacity: 2)

    do {
      try await reader.collect(into: &target)
      Issue.record("Expected error")
    } catch {
      let expected = EitherError<Never, AsyncReaderLeftOverElementsError>.second(AsyncReaderLeftOverElementsError())
      #expect(error == expected)
    }
  }

  @Test
  func collectIntoEmptyReader() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 0, copying: []))
    var target = RigidArray<Int>(capacity: 5)

    try await reader.collect(into: &target)

    #expect(target.count == 0)
  }
}

@Suite
struct AsyncReaderCollectExactlyTests {
  @Test
  func collectExactlyFillsTargetWhenReaderProducesExactCount() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var target = RigidArray<Int>(capacity: 3)

    try await reader.collect(exactlyInto: &target)

    var collected: [Int] = []
    var c = target.consumeAll()
    while let v = c.next() { collected.append(v) }
    #expect(collected == [1, 2, 3])
  }

  @Test
  func collectExactlyThrowsWhenReaderProducesFewer() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var target = RigidArray<Int>(capacity: 5)

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
  }

  @Test
  func collectExactlyThrowsWhenReaderProducesMore() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var target = RigidArray<Int>(capacity: 2)

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
  }
}

@Suite
struct AsyncReaderCollectIntoMaximumSizeTests {
  @Test
  func collectGrowsContainerWhenReaderHasFewerThanMaximum() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [1, 2, 3]))
    var target = UniqueArray<Int>()

    try await reader.collect(into: &target, maximumSize: 10)

    var collected: [Int] = []
    var c = target.consumeAll()
    while let v = c.next() { collected.append(v) }
    #expect(collected == [1, 2, 3])
  }

  @Test
  func collectFillsContainerExactlyAtMaximum() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 3, copying: [10, 20, 30]))
    var target = UniqueArray<Int>()

    try await reader.collect(into: &target, maximumSize: 3)

    #expect(target.count == 3)
  }

  @Test
  func collectThrowsWhenReaderProducesMoreThanMaximum() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 5, copying: [1, 2, 3, 4, 5]))
    var target = UniqueArray<Int>()

    do {
      try await reader.collect(into: &target, maximumSize: 2)
      Issue.record("Expected error")
    } catch {
      let expected = EitherError<Never, AsyncReaderLeftOverElementsError>.second(AsyncReaderLeftOverElementsError())
      #expect(error == expected)
    }
  }

  @Test
  func collectAppendsToExistingContents() async throws {
    let reader = UniqueArrayAsyncReader(storage: UniqueArray(capacity: 2, copying: [3, 4]))
    var target = UniqueArray<Int>(capacity: 2, copying: [1, 2])

    try await reader.collect(into: &target, maximumSize: 10)

    var collected: [Int] = []
    var c = target.consumeAll()
    while let v = c.next() { collected.append(v) }
    #expect(collected == [1, 2, 3, 4])
  }
}

#endif

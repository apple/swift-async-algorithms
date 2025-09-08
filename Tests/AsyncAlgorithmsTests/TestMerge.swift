//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
import AsyncAlgorithms

final class TestMerge2: XCTestCase {
  func test_merge_makes_sequence_with_elements_from_sources_when_all_have_same_size() async {
    let first = [1, 2, 3]
    let second = [4, 5, 6]

    let merged = merge(first.async, second.async)
    var collected = [Int]()
    let expected = Set(first + second).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_first_is_longer() async {
    let first = [1, 2, 3, 4, 5, 6, 7]
    let second = [8, 9, 10]

    let merged = merge(first.async, second.async)
    var collected = [Int]()
    let expected = Set(first + second).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_second_is_longer() async {
    let first = [1, 2, 3]
    let second = [4, 5, 6, 7]

    let merged = merge(first.async, second.async)
    var collected = [Int]()
    let expected = Set(first + second).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_produces_three_elements_from_first_and_throws_when_first_is_longer_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3, 4, 5]
    let second = [6, 7, 8]

    let merged = merge(first.async.map { try throwOn(4, $0) }, second.async)
    var collected = Set<Int>()
    let expected = Set([1, 2, 3])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the first sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func
    test_merge_produces_three_elements_from_first_and_throws_when_first_is_shorter_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3, 4, 5]
    let second = [6, 7, 8, 9, 10, 11]

    let merged = merge(first.async.map { try throwOn(4, $0) }, second.async)
    var collected = Set<Int>()
    let expected = Set([1, 2, 3])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the first sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func
    test_merge_produces_three_elements_from_second_and_throws_when_second_is_longer_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3]
    let second = [4, 5, 6, 7, 8]

    let merged = merge(first.async, second.async.map { try throwOn(7, $0) })
    var collected = Set<Int>()
    let expected = Set([4, 5, 6])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the second sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func
    test_merge_produces_three_elements_from_second_and_throws_when_second_is_shorter_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3, 4, 5, 6, 7]
    let second = [7, 8, 9, 10, 11]

    let merged = merge(first.async, second.async.map { try throwOn(10, $0) })
    var collected = Set<Int>()
    let expected = Set([7, 8, 9])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the second sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)
  func test_merge_makes_sequence_with_ordered_elements_when_sources_follow_a_timeline() {
    validate {
      "a-c-e-g-|"
      "-b-d-f-h"
      merge($0.inputs[0], $0.inputs[1])
      "abcdefgh|"
    }
  }
  #endif

  func test_merge_finishes_when_iteration_task_is_cancelled() async {
    let source1 = Indefinite(value: "test1")
    let source2 = Indefinite(value: "test2")
    let sequence = merge(source1.async, source2.async)
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")
    let task = Task {
      var firstIteration = false
      for await _ in sequence {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }
    // ensure the other task actually starts
    await fulfillment(of: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    await fulfillment(of: [finished], timeout: 1.0)
  }

  func test_merge_when_cancelled() async {
    let t = Task {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      let c1 = Indefinite(value: "test1").async
      let c2 = Indefinite(value: "test1").async
      for await _ in merge(c1, c2) {}
    }
    t.cancel()
  }
}

final class TestMerge3: XCTestCase {
  func test_merge_makes_sequence_with_elements_from_sources_when_all_have_same_size() async {
    let first = [1, 2, 3]
    let second = [4, 5, 6]
    let third = [7, 8, 9]

    let merged = merge(first.async, second.async, third.async)
    var collected = [Int]()
    let expected = Set(first + second + third).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_first_is_longer() async {
    let first = [1, 2, 3, 4, 5]
    let second = [6, 7, 8]
    let third = [9, 10, 11]

    let merged = merge(first.async, second.async, third.async)
    var collected = [Int]()
    let expected = Set(first + second + third).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_second_is_longer() async {
    let first = [1, 2, 3]
    let second = [4, 5, 6, 7, 8]
    let third = [9, 10, 11]

    let merged = merge(first.async, second.async, third.async)
    var collected = [Int]()
    let expected = Set(first + second + third).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_third_is_longer() async {
    let first = [1, 2, 3]
    let second = [4, 5, 6]
    let third = [7, 8, 9, 10, 11]

    let merged = merge(first.async, second.async, third.async)
    var collected = [Int]()
    let expected = Set(first + second + third).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_first_and_second_are_longer() async {
    let first = [1, 2, 3, 4, 5]
    let second = [6, 7, 8, 9]
    let third = [10, 11]

    let merged = merge(first.async, second.async, third.async)
    var collected = [Int]()
    let expected = Set(first + second + third).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_first_and_third_are_longer() async {
    let first = [1, 2, 3, 4, 5]
    let second = [6, 7]
    let third = [8, 9, 10, 11]

    let merged = merge(first.async, second.async, third.async)
    var collected = [Int]()
    let expected = Set(first + second + third).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_makes_sequence_with_elements_from_sources_when_second_and_third_are_longer() async {
    let first = [1, 2, 3]
    let second = [4, 5, 6, 7]
    let third = [8, 9, 10, 11]

    let merged = merge(first.async, second.async, third.async)
    var collected = [Int]()
    let expected = Set(first + second + third).sorted()

    var iterator = merged.makeAsyncIterator()
    while let item = await iterator.next() {
      collected.append(item)
    }
    let pastEnd = await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(Set(collected).sorted(), expected)
  }

  func test_merge_produces_three_elements_from_first_and_throws_when_first_is_longer_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3, 4, 5]
    let second = [6, 7, 8]
    let third = [9, 10, 11]

    let merged = merge(first.async.map { try throwOn(4, $0) }, second.async, third.async)
    var collected = Set<Int>()
    let expected = Set([1, 2, 3])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the first sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func
    test_merge_produces_three_elements_from_first_and_throws_when_first_is_shorter_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3, 4, 5]
    let second = [6, 7, 8, 9, 10, 11]
    let third = [12, 13, 14]

    let merged = merge(first.async.map { try throwOn(4, $0) }, second.async, third.async)
    var collected = Set<Int>()
    let expected = Set([1, 2, 3])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the first sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func
    test_merge_produces_three_elements_from_second_and_throws_when_second_is_longer_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3]
    let second = [4, 5, 6, 7, 8]
    let third = [9, 10, 11]

    let merged = merge(first.async, second.async.map { try throwOn(7, $0) }, third.async)
    var collected = Set<Int>()
    let expected = Set([4, 5, 6])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the second sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func
    test_merge_produces_three_elements_from_second_and_throws_when_second_is_shorter_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3, 4, 5, 6, 7]
    let second = [7, 8, 9, 10, 11]
    let third = [12, 13, 14]

    let merged = merge(first.async, second.async.map { try throwOn(10, $0) }, third.async)
    var collected = Set<Int>()
    let expected = Set([7, 8, 9])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the second sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func test_merge_produces_three_elements_from_third_and_throws_when_third_is_longer_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3]
    let second = [4, 5, 6]
    let third = [7, 8, 9, 10, 11]

    let merged = merge(first.async, second.async, third.async.map { try throwOn(10, $0) })
    var collected = Set<Int>()
    let expected = Set([7, 8, 9])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the third sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  func
    test_merge_produces_three_elements_from_third_and_throws_when_third_is_shorter_and_throws_after_three_elements()
    async throws
  {
    let first = [1, 2, 3, 4, 5, 6, 7]
    let second = [7, 8, 9, 10, 11]
    let third = [12, 13, 14, 15]

    let merged = merge(first.async, second.async, third.async.map { try throwOn(15, $0) })
    var collected = Set<Int>()
    let expected = Set([12, 13, 14])

    var iterator = merged.makeAsyncIterator()
    do {
      while let item = try await iterator.next() {
        collected.insert(item)
      }
      XCTFail("Merged sequence should throw after collecting three first elements from the third sequence")
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    let pastEnd = try await iterator.next()

    XCTAssertNil(pastEnd)
    XCTAssertEqual(collected.intersection(expected), expected)
  }

  #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)
  func test_merge_makes_sequence_with_ordered_elements_when_sources_follow_a_timeline() {
    validate {
      "a---e---|"
      "-b-d-f-h|"
      "--c---g-|"
      merge($0.inputs[0], $0.inputs[1], $0.inputs[2])
      "abcdefgh|"
    }
  }
  #endif

  func test_merge_finishes_when_iteration_task_is_cancelled() async {
    let source1 = Indefinite(value: "test1")
    let source2 = Indefinite(value: "test2")
    let source3 = Indefinite(value: "test3")
    let sequence = merge(source1.async, source2.async, source3.async)
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")
    let task = Task {
      var firstIteration = false
      for await _ in sequence {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }
    // ensure the other task actually starts
    await fulfillment(of: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    await fulfillment(of: [finished], timeout: 1.0)
  }

  // MARK: - IteratorInitialized

  func testIteratorInitialized_whenInitial() async throws {
    let reportingSequence1 = ReportingAsyncSequence([1])
    let reportingSequence2 = ReportingAsyncSequence([2])
    let merge = merge(reportingSequence1, reportingSequence2)

    _ = merge.makeAsyncIterator()

    // We need to give the task that consumes the upstream
    // a bit of time to make the iterators
    try await Task.sleep(nanoseconds: 1_000_000)

    XCTAssertEqual(reportingSequence1.events, [])
    XCTAssertEqual(reportingSequence2.events, [])
  }

  // MARK: - IteratorDeinitialized

  func testIteratorDeinitialized_whenMerging() async throws {
    let merge = merge([1].async, [2].async)

    var iterator: _! = merge.makeAsyncIterator()

    let nextValue = await iterator.next()
    XCTAssertNotNil(nextValue)

    iterator = nil
  }

  func testIteratorDeinitialized_whenFinished() async throws {
    let merge = merge([Int]().async, [].async)

    var iterator: _? = merge.makeAsyncIterator()
    let firstValue = await iterator?.next()
    XCTAssertNil(firstValue)

    iterator = nil
  }
}

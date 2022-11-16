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

@preconcurrency import XCTest
import AsyncAlgorithms

final class TestBroadcast: XCTestCase {
  
  func test_broadcast_basic() async {
    let expected = [1, 2, 3, 4]
    let base = GatedStartSequence(expected, count: 2)
    let sequence = base.broadcast()
    let results = await withTaskGroup(of: [Int].self) { group in
      group.addTask {
        var iterator = sequence.makeAsyncIterator()
        base.enter()
        return await iterator.collect()
      }
      group.addTask {
        var iterator = sequence.makeAsyncIterator()
        base.enter()
        return await iterator.collect()
      }
      return await Array(group)
    }
    XCTAssertEqual(expected, results[0])
    XCTAssertEqual(expected, results[1])
  }
  
  func test_broadcast_iterator_iterates_past_end() async {
    let base = GatedStartSequence([1, 2, 3, 4], count: 2)
    let sequence = base.broadcast()
    let results = await withTaskGroup(of: Int?.self) { group in
      group.addTask {
        var iterator = sequence.makeAsyncIterator()
        base.enter()
        let _ = await iterator.collect()
        return await iterator.next()
      }
      group.addTask {
        var iterator = sequence.makeAsyncIterator()
        base.enter()
        let _ = await iterator.collect()
        return await iterator.next()
      }
      return await Array(group)
    }
    XCTAssertNil(results[0])
    XCTAssertNil(results[1])
  }
  
  func test_broadcast_throws() async {
    let base = GatedStartSequence([1, 2, 3, 4], count: 2)
    let expected = [1, 2]
    let sequence = base.map { try throwOn(3, $0) }.broadcast()
    let results = await withTaskGroup(of: (elements: [Int], error: Error?).self) { group in
      group.addTask {
        var iterator = sequence.makeAsyncIterator()
        base.enter()
        return await iterator.collectWithError()
      }
      group.addTask {
        var iterator = sequence.makeAsyncIterator()
        base.enter()
        return await iterator.collectWithError()
      }
      return await Array(group)
    }
    XCTAssertEqual(expected, results[0].elements)
    XCTAssertEqual(expected, results[1].elements)
    XCTAssertNotNil(results[0].error as? Failure)
    XCTAssertNotNil(results[1].error as? Failure)
  }
  
  func test_broadcast_concurrent_consumer_wide() async throws {
    let noOfConsumers = 100
    let noOfEmissions = 100
    let expected = (0..<noOfEmissions).map { $0 }
    let base = GatedStartSequence(expected, count: noOfConsumers)
    let sequence = base.broadcast()
    let results = await withTaskGroup(of: [Int].self) { group in
      for _ in 0..<noOfConsumers {
        group.addTask {
          var iterator = sequence.makeAsyncIterator()
          base.enter()
          return await iterator.collect()
        }
      }
      return await Array(group)
    }
    let expectedElementCount = noOfConsumers * expected.count
    let expectedSumOfElements = noOfConsumers * expected.reduce(0, +)
    let elementCount = results.flatMap { $0 }.count
    let sumOfElements = results.flatMap { $0 }.reduce(0, +)
    XCTAssertEqual(expectedElementCount, elementCount)
    XCTAssertEqual(expectedSumOfElements, sumOfElements)
  }
  
  func test_broadcast_single_consumer_cancellation() async {
    let base = Indefinite(value: 1).async
    let sequence = base.broadcast()
    let iterated = expectation(description: "iterated")
    iterated.assertForOverFulfill = false
    let task = Task {
      var elements = [Int]()
      for await element in sequence {
        elements.append(element)
        iterated.fulfill()
      }
      return elements
    }
    wait(for: [iterated], timeout: 1.0)
    task.cancel()
    let result = await task.value
    XCTAssert(result.count > 0)
  }
  
  func test_broadcast_multiple_consumer_cancellation() async {
    let source = Indefinite(value: 1)
    let sequence = source.async.broadcast()
    var tasks = [Task<Void, Never>]()
    var iterated = [XCTestExpectation]()
    var finished = [XCTestExpectation]()
    for _ in 0..<16 {
      let iterate = expectation(description: "task iterated")
      iterate.assertForOverFulfill = false
      let finish = expectation(description: "task finished")
      iterated.append(iterate)
      finished.append(finish)
      let task = Task {
        var iterator = sequence.makeAsyncIterator()
        while let _ = await iterator.next() {
          iterate.fulfill()
        }
        finish.fulfill()
      }
      tasks.append(task)
    }
    wait(for: iterated, timeout: 1.0)
    for task in tasks { task.cancel() }
    wait(for: finished, timeout: 1.0)
  }
  
  func test_broadcast_iterator_retained_when_vacant_if_policy() async {
    let base = [0,1,2,3].async
    let sequence = base.broadcast(disposingBaseIterator: .whenTerminated)
    let expected0 = [0]
    let expected1 = [1]
    let expected2 = [2]
    let result0 = await sequence.prefix(1).reduce(into:[Int]()) { $0.append($1) }
    let result1 = await sequence.prefix(1).reduce(into:[Int]()) { $0.append($1) }
    let result2 = await sequence.prefix(1).reduce(into:[Int]()) { $0.append($1) }
    XCTAssertEqual(expected0, result0)
    XCTAssertEqual(expected1, result1)
    XCTAssertEqual(expected2, result2)
  }
  
  func test_broadcast_iterator_discarded_when_vacant_if_policy() async {
    let base = [0,1,2,3].async
    let sequence = base.broadcast(disposingBaseIterator: .whenTerminatedOrVacant)
    let expected0 = [0]
    let expected1 = [0]
    let expected2 = [0]
    let result0 = await sequence.prefix(1).reduce(into:[Int]()) { $0.append($1) }
    let result1 = await sequence.prefix(1).reduce(into:[Int]()) { $0.append($1) }
    let result2 = await sequence.prefix(1).reduce(into:[Int]()) { $0.append($1) }
    XCTAssertEqual(expected0, result0)
    XCTAssertEqual(expected1, result1)
    XCTAssertEqual(expected2, result2)
  }
  
  func test_broadcast_iterator_discarded_when_terminal_regardless_of_policy() async {
    let base = [0,1,2,3].async
    let sequence = base.broadcast(disposingBaseIterator: .whenTerminated)
    let expected0 = [0,1,2,3]
    let expected1 = [Int]()
    let expected2 = [Int]()
    let result0 = await sequence.reduce(into:[Int]()) { $0.append($1) }
    let result1 = await sequence.reduce(into:[Int]()) { $0.append($1) }
    let result2 = await sequence.reduce(into:[Int]()) { $0.append($1) }
    XCTAssertEqual(expected0, result0)
    XCTAssertEqual(expected1, result1)
    XCTAssertEqual(expected2, result2)
  }
  
  func test_broadcast_iterator_discarded_when_throws_regardless_of_policy() async {
    let base = [0,1,2,3].async.map { try throwOn(1, $0) }
    let sequence = base.broadcast(disposingBaseIterator: .whenTerminatedOrVacant)
    let expected0 = [0]
    let expected1 = [Int]()
    let expected2 = [Int]()
    var iterator0 = sequence.makeAsyncIterator()
    let result0 = await iterator0.collectWithError(count: 2)
    var iterator1 = sequence.makeAsyncIterator()
    let result1 = await iterator1.collectWithError(count: 2)
    var iterator2 = sequence.makeAsyncIterator()
    let result2 = await iterator2.collectWithError(count: 2)
    XCTAssertEqual(expected0, result0.elements)
    XCTAssertEqual(expected1, result1.elements)
    XCTAssertEqual(expected2, result2.elements)
    XCTAssertNotNil(result0.error as? Failure)
    XCTAssertNil(result1.error)
    XCTAssertNil(result2.error)
  }
  
  func test_broadcast_history_count_0() async throws {
    let p0 = ["a","b","c","d"]
    let p1 = ["e","f","g","h"]
    let p2 = ["i","j","k","l"]
    let p3 = ["m","n","o","p"]
    let base = GatedSequence(p0 + p1 + p2 + p3)
    let sequence = base.broadcast(history: 0)
    let expected = [["e", "f"], ["i", "j"], ["m", "n"]]
    let gate = Gate()
    for _ in 0..<p0.count { base.advance() }
    Task {
      for await el in sequence {
        switch el {
        case "d": gate.open()
        case "h": gate.open()
        case "l": gate.open()
        case "p": gate.open()
        default: break
        }
      }
    }
    await gate.enter()
    let results0 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p1.count { base.advance() }
      let results = await iterator.collect(count: 2) // e, f
      return results
    }.value
    await gate.enter()
    let results1 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p2.count { base.advance() }
      let results = await iterator.collect(count: 2) // i, j
      return results
    }.value
    await gate.enter()
    let results2 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p3.count { base.advance() }
      let results = await iterator.collect(count: 2) // m, n
      return results
    }.value
    XCTAssertEqual(expected[0], results0)
    XCTAssertEqual(expected[1], results1)
    XCTAssertEqual(expected[2], results2)
  }
  
  func test_broadcast_history_count_1() async throws {
    let p0 = ["a","b","c","d"]
    let p1 = ["e","f","g","h"]
    let p2 = ["i","j","k","l"]
    let p3 = ["m","n","o","p"]
    let base = GatedSequence(p0 + p1 + p2 + p3)
    let sequence = base.broadcast(history: 1)
    let expected = [["d", "e"], ["h", "i"], ["l", "m"]]
    let gate = Gate()
    for _ in 0..<p0.count { base.advance() }
    Task {
      for await el in sequence {
        switch el {
        case "d": gate.open()
        case "h": gate.open()
        case "l": gate.open()
        case "p": gate.open()
        default: break
        }
      }
    }
    await gate.enter()
    let results0 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p1.count { base.advance() }
      let results = await iterator.collect(count: 2) // e, f
      return results
    }.value
    await gate.enter()
    let results1 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p2.count { base.advance() }
      let results = await iterator.collect(count: 2) // i, j
      return results
    }.value
    await gate.enter()
    let results2 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p3.count { base.advance() }
      let results = await iterator.collect(count: 2) // m, n
      return results
    }.value
    XCTAssertEqual(expected[0], results0)
    XCTAssertEqual(expected[1], results1)
    XCTAssertEqual(expected[2], results2)
  }
  
  func test_broadcast_history_count_2() async throws {
    let p0 = ["a","b","c","d"]
    let p1 = ["e","f","g","h"]
    let p2 = ["i","j","k","l"]
    let p3 = ["m","n","o","p"]
    let base = GatedSequence(p0 + p1 + p2 + p3)
    let sequence = base.broadcast(history: 2)
    let expected = [["c", "d"], ["g", "h"], ["k", "l"]]
    let gate = Gate()
    for _ in 0..<p0.count { base.advance() }
    Task {
      for await el in sequence {
        switch el {
        case "d": gate.open()
        case "h": gate.open()
        case "l": gate.open()
        case "p": gate.open()
        default: break
        }
      }
    }
    await gate.enter()
    let results0 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p1.count { base.advance() }
      let results = await iterator.collect(count: 2) // e, f
      return results
    }.value
    await gate.enter()
    let results1 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p2.count { base.advance() }
      let results = await iterator.collect(count: 2) // i, j
      return results
    }.value
    await gate.enter()
    let results2 = await Task {
      var iterator = sequence.makeAsyncIterator()
      for _ in 0..<p3.count { base.advance() }
      let results = await iterator.collect(count: 2) // m, n
      return results
    }.value
    XCTAssertEqual(expected[0], results0)
    XCTAssertEqual(expected[1], results1)
    XCTAssertEqual(expected[2], results2)
  }
  
  func test_broadcast_iterator_disposal_policy_when_terminated_or_vacant_discards_history_on_vacant() async {
    let expected = ["a","b","c","d"]
    let base = Array(["a","b","c","d"]).async
    let sequence = base.broadcast(history: 2, disposingBaseIterator: .whenTerminatedOrVacant)
    var result0 = [String]()
    var result1 = [String]()
    var result2 = [String]()
    for await el in sequence { result0.append(el); if el == "d" { break } }
    for await el in sequence { result1.append(el); if el == "d" { break } }
    for await el in sequence { result2.append(el); if el == "d" { break } }
    XCTAssertEqual(expected, result0)
    XCTAssertEqual(expected, result1)
    XCTAssertEqual(expected, result2)
  }
  
  func test_broadcast_iterator_disposal_policy_when_terminated_persists_history_on_vacant() async {
    let expected0 = ["a","b","c","d"]
    let expected1 = ["c","d"]
    let expected2 = ["c","d"]
    let base = Array(["a","b","c","d"]).async
    let sequence = base.broadcast(history: 2, disposingBaseIterator: .whenTerminated)
    var result0 = [String]()
    var result1 = [String]()
    var result2 = [String]()
    for await el in sequence { result0.append(el); if el == "d" { break } }
    for await el in sequence { result1.append(el); if el == "d" { break } }
    for await el in sequence { result2.append(el); if el == "d" { break } }
    XCTAssertEqual(expected0, result0)
    XCTAssertEqual(expected1, result1)
    XCTAssertEqual(expected2, result2)
  }
  
  func test_broadcast_shutdown_on_dealloc() async {
    typealias Sequence = AsyncBroadcastSequence<AsyncLazySequence<Indefinite<Int>>>
    let expected0: [Int] = [1]
    let expected1: [Int] = []
    let base = Indefinite(value: 1).async
    var sequence: Sequence! = base.broadcast()
    var iterator = sequence.makeAsyncIterator()
    let result0 = await iterator.collect(count: 1)
    sequence = nil
    let result1 = await iterator.collect()
    XCTAssertEqual(expected0, result0)
    XCTAssertEqual(expected1, result1)
  }
}

fileprivate extension AsyncIteratorProtocol {
  
  mutating func collect(count: Int = .max) async rethrows -> [Element] {
    var result = [Element]()
    var i = count
    while let element = try await next() {
      result.append(element)
      i -= 1
      if i <= 0 { return result }
    }
    return result
  }
  
  mutating func collectWithError(count: Int = .max) async -> (elements: [Element], error: Error?) {
    var result = [Element]()
    var i = count
    do {
      while let element = try await next() {
        result.append(element)
        i -= 1
        if i <= 0 { return (result, nil) }
      }
      return (result, nil)
    }
    catch {
      return (result, error)
    }
  }
}

//
//  TestZipLatestFrom.swift
//  
//
//  Created by Thibault Wittemberg on 01/04/2022.
//

import AsyncAlgorithms
@preconcurrency import XCTest

/// This spy will call the `onLatestKnownElement` function when `next()` is called but it will pass the latest known produced element from `Base` as an argument.
/// We can use the `onLatestKnownElement` callback to fulfill expectations when we need to be sure an element from `Base` has been consumed.
fileprivate struct AsyncSpySequence<Base: AsyncSequence>: AsyncSequence {
  typealias Element = Base.Element
  typealias AsyncIterator = Iterator

  let base: Base
  let onLatestKnownElement: (Base.Element) async -> Void

  init(
    _ other: Base,
    onLatestKnownElement: @escaping (Base.Element) async -> Void
  ) {
    self.base = other
    self.onLatestKnownElement = onLatestKnownElement
  }

  func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base: self.base.makeAsyncIterator(),
      onLatestKnownElement: self.onLatestKnownElement
    )
  }

  struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
    var lastKnownElement: Element? = nil
    let onLatestKnownElement: (Base.Element) async -> Void

    mutating func next() async rethrows -> Element? {
      if let nonNilLastKnownElement = self.lastKnownElement {
        await self.onLatestKnownElement(nonNilLastKnownElement)
      }

      let baseElement = try await self.base.next()
      self.lastKnownElement = baseElement
      return baseElement
    }
  }
}

final class TestZipLatestFrom: XCTestCase {}

// MARK: test for AsyncZipLatestSequence
extension TestZipLatestFrom {
  func test_zipLatestFrom_uses_latest_element_from_other() async {
    let otherHasProducedB = expectation(description: "Other has produced 'b'")

    let base = [1, 2, 3]
    let other = AsyncChannel<String>()
    let spyOther = AsyncSpySequence(other, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "b" {
        otherHasProducedB.fulfill()
      }
    })
    
    let sequence = base.async.zipLatest(from: spyOther)
    var iterator = sequence.makeAsyncIterator()
    await other.send("a")
    await other.send("b")

    wait(for: [otherHasProducedB], timeout: 1)

    var elements = [(Int, String)]()
    while let element = await iterator.next() {
      elements.append(element)
    }
    XCTAssertEqual(elements, [(1, "b"), (2, "b"), (3, "b")])
  }

  func test_zipLatestFrom_throws_when_base_throws() async {
    let base = [1, 2, 3]
    let other = AsyncChannel<String>()
    let sequence = base.async.map { try throwOn(1, $0) }.zipLatest(from: other)
    var iterator = sequence.makeAsyncIterator()

    await other.send("a")

    do {
      let value = try await iterator.next()
      XCTFail("got \(value as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }

  func test_zipLatestFrom_throws_when_other_throws() async {
    let base = Indefinite(value: 1)
    let other = AsyncThrowingChannel<String, Error>()
    let sequence = base.async.zipLatest(from: other)
    var iterator = sequence.makeAsyncIterator()

    await other.fail(Failure())

    do {
      var element: (Int, String)?
      repeat {
        element = try await iterator.next()
      } while element == nil
      XCTFail("got \(element as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }

  func test_zipLatestFrom_uses_latest_element_from_other_when_other_produces_first_elements() async {
    // Timeline
    // base:     ---1    -2    -----3    -|
    // other:    -a--    --    -b-c--    -|
    // expected: ---(1,a)-(2,a)-----(3,c)-|
    
    let otherHasProducedA = expectation(description: "Other has produced 'a'")
    let otherHasProducedC = expectation(description: "Other has produced 'c'")
    let finished = expectation(description: "finished")

    let base = AsyncChannel<Int>()
    let other = AsyncChannel<String>()
    let spyOther = AsyncSpySequence(other, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        otherHasProducedA.fulfill()
      }
      if latestKnownElement == "c" {
        otherHasProducedC.fulfill()
      }
    })

    let sequence = base.zipLatest(from: spyOther)

    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    var value = await validator.validate()
    XCTAssertEqual(value, [])

    await other.send("a")
    value = validator.current
    XCTAssertEqual(value, [])

    wait(for: [otherHasProducedA], timeout: 1)

    await base.send(1)
    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a")])

    await base.send(2)
    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a")])

    await other.send("b")
    await other.send("c")
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (2, "a")])

    wait(for: [otherHasProducedC], timeout: 1)

    await base.send(3)
    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (3, "c")])

    await base.finish()

    wait(for: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a"), (2, "a"), (3, "c")])
  }

  func test_zipLatestFrom_uses_latest_element_from_other_when_base_produces_first_elements() async {
    // Timeline
    // base:     -1-2---3    -4    ---5    -|
    // other:    -----a--    --    -b--    -|
    // expected: -------(3,a)-(4,a)---(5,b)-|

    let baseHasProduced2 = expectation(description: "Base has produced 2")

    let otherHasProducedA = expectation(description: "Other has produced 'a'")
    let otherHasProducedB = expectation(description: "Other has produced 'b'")

    let finished = expectation(description: "finished")

    let base = AsyncChannel<Int>()
    let other = AsyncChannel<String>()

    let spyBase = AsyncSpySequence(base, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == 2 {
        baseHasProduced2.fulfill()
      }
    })

    let spyOther = AsyncSpySequence(other, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        otherHasProducedA.fulfill()
      }
      if latestKnownElement == "b" {
        otherHasProducedB.fulfill()
      }
    })

    let sequence = spyBase.zipLatest(from: spyOther)

    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    var value = await validator.validate()
    XCTAssertEqual(value, [])

    await base.send(1)
    await base.send(2)

    wait(for: [baseHasProduced2], timeout: 1)

    await other.send("a")

    wait(for: [otherHasProducedA], timeout: 1)

    await base.send(3)

    value = await validator.validate()
    XCTAssertEqual(value, [(3, "a")])

    await base.send(4)
    value = await validator.validate()
    XCTAssertEqual(value, [(3, "a"), (4, "a")])

    await other.send("b")

    wait(for: [otherHasProducedB], timeout: 1)

    await base.send(5)
    value = await validator.validate()
    XCTAssertEqual(value, [(3, "a"), (4, "a"), (5, "b")])

    await base.finish()

    wait(for: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(3, "a"), (4, "a"), (5, "b")])
  }

  func test_zipLatestFrom_finishes_when_base_produces_an_element_while_other_is_finished() async {
    let finished = expectation(description: "finished")

    let base = Indefinite(value: 1)
    let other = AsyncChannel<String>()

    let sequence = base.async.zipLatest(from: other)

    let validator = Validator<(Int, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    await other.finish()

    wait(for: [finished], timeout: 1.0)
    let value = validator.current
    XCTAssertEqual(value, [])
  }

  func test_zipLatestFrom_finishes_loop_when_task_is_cancelled() async {
    let otherHasProducedAnElement = expectation(description: "Other has produced at least an element")
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let base = Indefinite(value: "base")
    let other = AsyncChannel<String>()

    let spyOther = AsyncSpySequence(other, onLatestKnownElement: { _ in
      otherHasProducedAnElement.fulfill()
    })

    let sequence = base.async.zipLatest(from: spyOther)
    let iterator = sequence.makeAsyncIterator()

    await other.send("other")

    wait(for: [otherHasProducedAnElement], timeout: 1)

    let task = Task {
      var mutableIterator = iterator
      var firstIteration = false
      while let _ = await mutableIterator.next() {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }
    // ensure the other task actually starts
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

// MARK: test for AsyncZipLatest2Sequence
extension TestZipLatestFrom {
  func test_zipLatestFrom2_uses_latest_element_from_others() async {
    let other1HasProducedB = expectation(description: "Other has produced 'b'")
    let other2HasProducedB = expectation(description: "Other has produced 'b'")

    let base = [1, 2, 3]
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let spyOther1 = AsyncSpySequence(other1, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "b" {
        other1HasProducedB.fulfill()
      }
    })

    let spyOther2 = AsyncSpySequence(other2, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "b" {
        other2HasProducedB.fulfill()
      }
    })

    let sequence = base.async.zipLatest(from: spyOther1, spyOther2)
    var iterator = sequence.makeAsyncIterator()
    await other1.send("a")
    await other1.send("b")

    await other2.send("a")
    await other2.send("b")

    wait(for: [other1HasProducedB, other2HasProducedB], timeout: 1)

    var elements = [(Int, String, String)]()
    while let element = await iterator.next() {
      elements.append(element)
    }
    XCTAssertEqual(elements, [(1, "b", "b"), (2, "b", "b"), (3, "b", "b")])
  }

  func test_zipLatestFrom2_throws_when_base_throws() async {
    let base = [1, 2, 3]
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let sequence = base.async.map { try throwOn(1, $0) }.zipLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    await other1.send("a")
    await other2.send("a")

    do {
      let value = try await iterator.next()
      XCTFail("got \(value as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }

  func test_zipLatestFrom2_throws_when_other1_throws() async {
    let base = Indefinite(value: 1)
    let other1 = AsyncThrowingChannel<String, Error>()
    let other2 = AsyncThrowingChannel<String, Error>()

    let sequence = base.async.zipLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    await other1.fail(Failure())
    await other2.send("a")

    do {
      var element: (Int, String, String)?
      repeat {
        element = try await iterator.next()
      } while element == nil
      XCTFail("got \(element as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }

  func test_zipLatestFrom2_throws_when_other2_throws() async {
    let base = Indefinite(value: 1)
    let other1 = AsyncThrowingChannel<String, Error>()
    let other2 = AsyncThrowingChannel<String, Error>()

    let sequence = base.async.zipLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    await other2.fail(Failure())
    await other1.send("a")

    do {
      var element: (Int, String, String)?
      repeat {
        element = try await iterator.next()
      } while element == nil
      XCTFail("got \(element as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? Failure, Failure())
    }
  }

  func test_zipLatestFrom2_uses_latest_element_from_others_when_others_produces_first_elements() async {
    // Timeline
    // base:     ---1      -2      -----3      -|
    // other1:   -a--      --      -b-c--      -|
    // other2:   -a--      --      -b-c--      -|
    // expected: ---(1,a,a)-(2,a,a)-----(3,c,c)-|

    let othersHaveProducedA = expectation(description: "Others have produced 'a'")
    othersHaveProducedA.expectedFulfillmentCount = 2
    let othersHaveProducedC = expectation(description: "Others have produced 'c'")
    othersHaveProducedC.expectedFulfillmentCount = 2

    let finished = expectation(description: "finished")

    let base = AsyncChannel<Int>()
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let spyOther1 = AsyncSpySequence(other1, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        othersHaveProducedA.fulfill()
      }
      if latestKnownElement == "c" {
        othersHaveProducedC.fulfill()
      }
    })

    let spyOther2 = AsyncSpySequence(other2, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        othersHaveProducedA.fulfill()
      }
      if latestKnownElement == "c" {
        othersHaveProducedC.fulfill()
      }
    })

    let sequence = base.zipLatest(from: spyOther1, spyOther2)

    let validator = Validator<(Int, String, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    var value = await validator.validate()
    XCTAssertEqual(value, [])

    await other1.send("a")
    await other2.send("a")
    value = validator.current
    XCTAssertEqual(value, [])

    wait(for: [othersHaveProducedA], timeout: 1)

    await base.send(1)
    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", "a")])

    await base.send(2)
    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", "a"), (2, "a", "a")])

    await other1.send("b")
    await other1.send("c")
    await other2.send("b")
    await other2.send("c")
    value = validator.current
    XCTAssertEqual(value, [(1, "a", "a"), (2, "a", "a")])

    wait(for: [othersHaveProducedC], timeout: 1)

    await base.send(3)
    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", "a"), (2, "a", "a"), (3, "c", "c")])

    await base.finish()

    wait(for: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(1, "a", "a"), (2, "a", "a"), (3, "c", "c")])
  }

  func test_zipLatestFrom2_uses_latest_element_from_others_when_other1_produces_first_element_then_base_then_other2() async {
    // Timeline
    // base:     |---1---2      -----3      -|
    // other1:   |-a------      -b-c--      -|
    // other2:   |-----a--      -b-c--      -|
    // expected: |-------(2,a,a)-----(3,c,c)-|

    let baseHasProduced1 = expectation(description: "Base has produced 1")
    let other1HasProducedA = expectation(description: "Other1 has produced 'a'")
    let other2HasProducedA = expectation(description: "Other2 has produced 'a'")
    let othersHaveProducedC = expectation(description: "Others have produced 'c'")
    othersHaveProducedC.expectedFulfillmentCount = 2
    let finished = expectation(description: "finished")

    let base = AsyncChannel<Int>()
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let spyBase = AsyncSpySequence(base, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == 1 {
        baseHasProduced1.fulfill()
      }
    })

    let spyOther1 = AsyncSpySequence(other1, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        other1HasProducedA.fulfill()
      }
      if latestKnownElement == "c" {
        othersHaveProducedC.fulfill()
      }
    })

    let spyOther2 = AsyncSpySequence(other2, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        other2HasProducedA.fulfill()
      }
      if latestKnownElement == "c" {
        othersHaveProducedC.fulfill()
      }
    })

    let sequence = spyBase.zipLatest(from: spyOther1, spyOther2)

    let validator = Validator<(Int, String, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    var value = await validator.validate()
    XCTAssertEqual(value, [])

    await other1.send("a")
    value = validator.current
    XCTAssertEqual(value, [])

    wait(for: [other1HasProducedA], timeout: 1)

    await base.send(1)
    value = validator.current
    XCTAssertEqual(value, [])

    wait(for: [baseHasProduced1], timeout: 1)

    await other2.send("a")
    value = validator.current
    XCTAssertEqual(value, [])

    wait(for: [other2HasProducedA], timeout: 1)

    await base.send(2)
    value = await validator.validate()
    XCTAssertEqual(value, [(2, "a", "a")])

    await other1.send("b")
    await other1.send("c")
    await other2.send("b")
    await other2.send("c")
    value = validator.current
    XCTAssertEqual(value, [(2, "a", "a")])

    wait(for: [othersHaveProducedC], timeout: 1)

    await base.send(3)
    value = await validator.validate()
    XCTAssertEqual(value, [(2, "a", "a"), (3, "c", "c")])

    await base.finish()

    wait(for: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(2, "a", "a"), (3, "c", "c")])
  }

  func test_zipLatestFrom2_uses_latest_element_from_others_when_base_produces_first_elements() async {
    // Timeline
    // base:     |-1-2---3      -4---------5      -|
    // other1:   |-----a--      --      -b--      -|
    // other2:   |-----a--      --      -b--      -|
    // expected: |-------(3,a,a)-(4,a,a)---(5,b,b)-|

    let baseHasProduced2 = expectation(description: "Base has produced 2")

    let othersHaveProducedA = expectation(description: "Others have produced 'a'")
    othersHaveProducedA.expectedFulfillmentCount = 2
    let othersHaveProducedB = expectation(description: "Others haver produced 'b'")
    othersHaveProducedB.expectedFulfillmentCount = 2

    let finished = expectation(description: "finished")

    let base = AsyncChannel<Int>()
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let spyBase = AsyncSpySequence(base, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == 2 {
        baseHasProduced2.fulfill()
      }
    })

    let spyOther1 = AsyncSpySequence(other1, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        othersHaveProducedA.fulfill()
      }
      if latestKnownElement == "b" {
        othersHaveProducedB.fulfill()
      }
    })

    let spyOther2 = AsyncSpySequence(other2, onLatestKnownElement: { latestKnownElement in
      if latestKnownElement == "a" {
        othersHaveProducedA.fulfill()
      }
      if latestKnownElement == "b" {
        othersHaveProducedB.fulfill()
      }
    })

    let sequence = spyBase.zipLatest(from: spyOther1, spyOther2)

    let validator = Validator<(Int, String, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    var value = await validator.validate()
    XCTAssertEqual(value, [])

    await base.send(1)
    await base.send(2)

    wait(for: [baseHasProduced2], timeout: 1)

    await other1.send("a")
    await other2.send("a")

    wait(for: [othersHaveProducedA], timeout: 1)

    await base.send(3)

    value = await validator.validate()
    XCTAssertEqual(value, [(3, "a", "a")])

    await base.send(4)
    value = await validator.validate()
    XCTAssertEqual(value, [(3, "a", "a"), (4, "a", "a")])

    await other1.send("b")
    await other2.send("b")

    wait(for: [othersHaveProducedB], timeout: 1)

    await base.send(5)
    value = await validator.validate()
    XCTAssertEqual(value, [(3, "a", "a"), (4, "a", "a"), (5, "b", "b")])

    await base.finish()

    wait(for: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(value, [(3, "a", "a"), (4, "a", "a"), (5, "b", "b")])
  }

  func test_zipLatestFrom2_finishes_when_base_produces_an_element_while_other1_is_finished() async {
    let finished = expectation(description: "finished")

    let base = Indefinite(value: 1)
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let sequence = base.async.zipLatest(from: other1, other2)

    let validator = Validator<(Int, String, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    await other1.finish()
    await other2.send("a")

    wait(for: [finished], timeout: 1.0)
    let value = validator.current
    XCTAssertEqual(value, [])
  }

  func test_zipLatestFrom2_finishes_when_base_produces_an_element_while_other2_is_finished() async {
    let finished = expectation(description: "finished")

    let base = Indefinite(value: 1)
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let sequence = base.async.zipLatest(from: other1, other2)

    let validator = Validator<(Int, String, String)>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }

    await other1.send("a")
    await other2.finish()

    wait(for: [finished], timeout: 1.0)
    let value = validator.current
    XCTAssertEqual(value, [])
  }

  func test_zipLatestFrom2_finishes_loop_when_task_is_cancelled() async {
    let othersHaveProducedAnElement = expectation(description: "Others have produced at least an element")
    othersHaveProducedAnElement.expectedFulfillmentCount = 2
    let finished = expectation(description: "finished")
    let iterated = expectation(description: "iterated")

    let base = Indefinite(value: "base")
    let other1 = AsyncChannel<String>()
    let other2 = AsyncChannel<String>()

    let spyOther1 = AsyncSpySequence(other1, onLatestKnownElement: { _ in
      othersHaveProducedAnElement.fulfill()
    })

    let spyOther2 = AsyncSpySequence(other2, onLatestKnownElement: { _ in
      othersHaveProducedAnElement.fulfill()
    })

    let sequence = base.async.zipLatest(from: spyOther1, spyOther2)
    let iterator = sequence.makeAsyncIterator()

    await other1.send("other")
    await other2.send("other")

    wait(for: [othersHaveProducedAnElement], timeout: 1)

    let task = Task {
      var mutableIterator = iterator
      var firstIteration = false
      while let _ = await mutableIterator.next() {
        if !firstIteration {
          firstIteration = true
          iterated.fulfill()
        }
      }
      finished.fulfill()
    }
    // ensure the other task actually starts
    wait(for: [iterated], timeout: 1.0)
    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}

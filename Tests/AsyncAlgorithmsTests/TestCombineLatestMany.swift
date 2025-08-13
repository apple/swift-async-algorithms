//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
import AsyncAlgorithms

@available(AsyncAlgorithms 1.1, *)
final class TestCombineLatestMany: XCTestCase {
  func test_combineLatest() async throws {
    let a = [1, 2, 3].async.mappedFailureToError
    let b = [4, 5, 6].async.mappedFailureToError
    let c = [7, 8, 9].async.mappedFailureToError
    let sequence = combineLatestMany([a, b, c])
    let actual = try await Array(sequence)
    XCTAssertGreaterThanOrEqual(actual.count, 3)
  }

  func test_ordering1() async {
    var a = GatedSequence([1, 2, 3]).mappedFailureToError
    var b = GatedSequence([4, 5, 6]).mappedFailureToError
    var c = GatedSequence([7, 8, 9]).mappedFailureToError
    let finished = expectation(description: "finished")
    let sequence = combineLatestMany([a, b, c])
    let validator = Validator<[Int]>()
    validator.test(sequence) { iterator in
      let pastEnd = await iterator.next()
      XCTAssertNil(pastEnd)
      finished.fulfill()
    }
    var value = await validator.validate()
    XCTAssertEqual(value, [])
    a.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    b.advance()
    value = validator.current
    XCTAssertEqual(value, [])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4)])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4)])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4)])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5)])
    a.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5)])
    b.advance()

    value = await validator.validate()
    XCTAssertEqual(value, [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5), (3, "c", 5)])
    c.advance()

    value = await validator.validate()
    XCTAssertEqual(
      value,
      [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5), (3, "c", 5), (3, "c", 6)]
    )

    await fulfillment(of: [finished], timeout: 1.0)
    value = validator.current
    XCTAssertEqual(
      value,
      [(1, "a", 4), (2, "a", 4), (2, "b", 4), (2, "b", 5), (3, "b", 5), (3, "c", 5), (3, "c", 6)]
    )
  }
}

@available(AsyncAlgorithms 1.1, *)
private struct MappingErrorAsyncSequence<Upstream: AsyncSequence & Sendable>: AsyncSequence, Sendable where Upstream.Failure == Never {
    var upstream: Upstream
    func makeAsyncIterator() -> Iterator {
        Iterator(upstream: upstream.makeAsyncIterator())
    }
    struct Iterator: AsyncIteratorProtocol {
        var upstream: Upstream.AsyncIterator
        mutating func next(isolation actor: isolated (any Actor)?) async throws -> Upstream.Element? {
            await upstream.next(isolation: actor)
        }
    }
}

@available(AsyncAlgorithms 1.1, *)
extension AsyncSequence where Failure == Never, Self: Sendable {
    var mappedFailureToError: some AsyncSequence<Element, any Error> & Sendable {
        MappingErrorAsyncSequence(upstream: self)
    }
}

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

final class TestAdjacentPairs: XCTestCase {
    func test_adjacentPairs() async {
        let source = 1...5
        let expected = [(1,2), (2,3), (3,4), (4,5)]
        let sequence = source.async.adjacentPairs()
        var actual: [(Int, Int)] = []
        for await item in sequence {
            actual.append(item)
        }
        XCTAssertEqual(expected, actual)
    }

    func test_empty() async {
        let source = 0..<1
        let expected: [(Int, Int)] = []
        let sequence = source.async.adjacentPairs()
        var actual: [(Int, Int)] = []
        for await item in sequence {
            actual.append(item)
        }
        XCTAssertEqual(expected, actual)
    }

    func test_cancellation() async {
        let source = Indefinite(value: 0)
        let sequence = source.async.adjacentPairs()
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
        wait(for: [iterated], timeout: 1.0)
        // cancellation should ensure the loop finishes
        // without regards to the remaining underlying sequence
        task.cancel()
        wait(for: [finished], timeout: 1.0)
    }
}

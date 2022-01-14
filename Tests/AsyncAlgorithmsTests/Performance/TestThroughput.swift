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

final class TestThroughput: XCTestCase {
    func test_chain2() async {
        await measureSequenceThroughput(output: 1) {
            chain($0, [].async)
        }
    }
    func test_chain3() async {
        await measureSequenceThroughput(output: 1) {
            chain($0, [].async, [].async)
        }
    }
    func test_compacted() async {
        await measureSequenceThroughput(output: .some(1)) {
            $0.compacted()
        }
    }
    func test_interspersed() async {
        await measureSequenceThroughput(output: 1) {
            $0.interspersed(with: 0)
        }
    }
    func test_merge2() async {
        await measureSequenceThroughput(output: 1) {
            merge($0, (0..<10).async)
        }
    }
    func test_merge3() async {
        await measureSequenceThroughput(output: 1) {
            merge($0, (0..<10).async, (0..<10).async)
        }
    }
    func test_removeDuplicates() async {
        await measureSequenceThroughput(source: (1...).async) {
            $0.removeDuplicates()
        }
    }
    func test_zip2() async {
        await measureSequenceThroughput(output: 1) {
            zip($0, Indefinite(value: 2).async)
        }
    }
    func test_zip3() async {
        await measureSequenceThroughput(output: 1) {
            zip($0, Indefinite(value: 2).async, Indefinite(value: 3).async)
        }
    }
}

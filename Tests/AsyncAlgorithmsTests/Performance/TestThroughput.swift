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

#if canImport(Darwin)
final class TestThroughput: XCTestCase {
  func test_chain2() async {
    await measureSequenceThroughput(firstOutput: 1, secondOutput: 2) {
      chain($0, $1)
    }
  }
  func test_chain3() async {
    await measureSequenceThroughput(firstOutput: 1, secondOutput: 2, thirdOutput: 3) {
      chain($0, $1, $2)
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
  func test_joined() async {
    await measureSequenceThroughput(output: [1, 2, 3, 4, 5].async) {
      $0.joined(separator: [0, 0, 0, 0, 0].async)
    }
  }
  func test_merge2() async {
    await measureSequenceThroughput(firstOutput: 1, secondOutput: 2) {
      merge($0, $1)
    }
  }
  func test_merge3() async {
    await measureSequenceThroughput(firstOutput: 1, secondOutput: 2, thirdOutput: 3) {
      merge($0, $1, $2)
    }
  }
  func test_removeDuplicates() async {
    await measureSequenceThroughput(source: (1...).async) {
      $0.removeDuplicates()
    }
  }
  func test_zip2() async {
    await measureSequenceThroughput(firstOutput: 1, secondOutput: 2) {
      zip($0, $1)
    }
  }
  func test_zip3() async {
    await measureSequenceThroughput(firstOutput: 1, secondOutput: 2, thirdOutput: 3) {
      zip($0, $1, $2)
    }
  }
}
#endif

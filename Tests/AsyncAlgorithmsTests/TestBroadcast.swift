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
  func test_basic_broadcasting() async {
    let base = [1, 2, 3, 4].async
    let a = base.broadcast()
    let b = a
    let results = await withTaskGroup(of: [Int].self) { group in
      group.addTask {
        await Array(a)
      }
      group.addTask {
        await Array(b)
      }
      return await Array(group)
    }
    XCTAssertEqual(results[0], results[1])
  }
  
  func test_basic_broadcasting_from_channel() async {
    let base = AsyncChannel<Int>()
    let a = base.broadcast()
    let b = a
    let results = await withTaskGroup(of: [Int].self) { group in
      group.addTask {
        var sent = [Int]()
        for i in 0..<10 {
          sent.append(i)
          await base.send(i)
        }
        base.finish()
        return sent
      }
      group.addTask {
        await Array(a)
      }
      group.addTask {
        await Array(b)
      }
      return await Array(group)
    }
    XCTAssertEqual(results[0], results[1])
  }
}

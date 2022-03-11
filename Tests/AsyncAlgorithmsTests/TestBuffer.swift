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

final class TestBuffer: XCTestCase {
  func test_buffering() async {
    var gated = GatedSequence([1, 2, 3, 4, 5])
    let sequence = gated.buffer(policy: .unbounded)
    var iterator = sequence.makeAsyncIterator()
    
    gated.advance()
    var value = await iterator.next()
    XCTAssertEqual(value, 1)
    gated.advance()
    gated.advance()
    gated.advance()
    value = await iterator.next()
    XCTAssertEqual(value, 2)
    value = await iterator.next()
    XCTAssertEqual(value, 3)
    value = await iterator.next()
    XCTAssertEqual(value, 4)
    gated.advance()
    gated.advance()
    value = await iterator.next()
    XCTAssertEqual(value, 5)
    value = await iterator.next()
    XCTAssertEqual(value, nil)
    value = await iterator.next()
    XCTAssertEqual(value, nil)
  }

  func test_buffering_withError() async {
    var gated = GatedSequence([1, 2, 3, 4, 5, 6, 7])
    let gated_map = gated.map { try throwOn(3, $0) }
    let sequence = gated_map.buffer(policy: .unbounded)
    var iterator = sequence.makeAsyncIterator()

    gated.advance()
    var value = try! await iterator.next()
    XCTAssertEqual(value, 1)
    gated.advance()
    gated.advance()
    gated.advance()
    value = try! await iterator.next()
    XCTAssertEqual(value, 2)

    gated.advance()
    gated.advance()
    gated.advance()
    gated.advance()
    do {
      value = try await iterator.next()
      XCTFail("next() should have thrown.")
    } catch { }

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)
  }
  
  func test_buffer_delegation() async {
    actor BufferDelegate: AsyncBuffer {
      var buffer = [Int]()
      var pushed = [Int]()
      
      func push(_ element: Int) async {
        buffer.append(element)
        pushed.append(element)
      }
      
      func pop() async -> Int? {
        if buffer.count > 0 {
          return buffer.removeFirst()
        }
        return nil
      }
    }
    let delegate = BufferDelegate()
    var gated = GatedSequence([1, 2, 3, 4, 5])
    let sequence = gated.buffer {
      delegate
    }
    var iterator = sequence.makeAsyncIterator()
    
    gated.advance()
    var value = await iterator.next()
    var pushed = await delegate.pushed
    XCTAssertEqual(pushed, [1])
    XCTAssertEqual(value, 1)
    gated.advance()
    gated.advance()
    gated.advance()
    value = await iterator.next()
    XCTAssertEqual(value, 2)
    value = await iterator.next()
    pushed = await delegate.pushed
    XCTAssertEqual(value, 3)
    value = await iterator.next()
    pushed = await delegate.pushed
    XCTAssertEqual(pushed, [1, 2, 3, 4])
    XCTAssertEqual(value, 4)
    gated.advance()
    gated.advance()
    value = await iterator.next()
    pushed = await delegate.pushed
    XCTAssertEqual(pushed, [1, 2, 3, 4, 5])
    XCTAssertEqual(value, 5)
    value = await iterator.next()
    XCTAssertEqual(value, nil)
    value = await iterator.next()
    XCTAssertEqual(value, nil)
  }

  func test_delegatedBuffer_withError() async {
    actor BufferDelegate: AsyncBuffer {
      var buffer = [Int]()
      var pushed = [Int]()

      func push(_ element: Int) async {
        buffer.append(element)
        pushed.append(element)
      }

      func pop() async throws -> Int? {
        if buffer.count > 0 {
          let value = buffer.removeFirst()
          if value == 3 {
            throw Failure()
          }
          return value
        }
        return nil
      }
    }
    let delegate = BufferDelegate()

    var gated = GatedSequence([1, 2, 3, 4, 5, 6, 7])
    let sequence = gated.buffer { delegate }
    var iterator = sequence.makeAsyncIterator()

    gated.advance()
    var value = try! await iterator.next()
    XCTAssertEqual(value, 1)
    gated.advance()
    gated.advance()
    gated.advance()
    value = try! await iterator.next()
    XCTAssertEqual(value, 2)

    gated.advance()
    gated.advance()
    gated.advance()
    gated.advance()
    do {
      value = try await iterator.next()
      XCTFail("next() should have thrown.")
    } catch { }

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)

    value = try! await iterator.next()
    XCTAssertNil(value)
  }
  
  func test_byteBuffer() async {
    actor ByteBuffer: AsyncBuffer {
      var buffer: [UInt8]?
      
      func push(_ element: UInt8) async {
        if buffer == nil {
          buffer = [UInt8]()
        }
        buffer?.append(element)
      }
      
      func pop() async -> [UInt8]? {
        defer { buffer = nil }
        return buffer
      }
    }
    
    var data = Data()
    for _ in 0..<4096 {
      data.append(UInt8.random(in: 0..<UInt8.max))
    }
    let buffered = data.async.buffer {
      ByteBuffer()
    }
    var collected = Data()
    for await segment in buffered {
      collected.append(contentsOf: segment)
    }
    XCTAssertEqual(data, collected)
  }

  func test_bufferingOldest() async {
    validate {
      "X-12-   34-    5   |"
      $0.inputs[0].buffer(policy: .bufferingOldest(2))
      "X,,,[1,],,[2,],[3,][5,]|"
    }
  }

  func test_bufferingOldest_noDrops() async {
    validate {
      "X-12   3   4   5   |"
      $0.inputs[0].buffer(policy: .bufferingOldest(2))
      "X,,[1,][2,][3,][45]|"
    }
  }

  func test_bufferingOldest_error() async {
    validate {
      "X-12345^"
      $0.inputs[0].buffer(policy: .bufferingOldest(2))
      "X,,,,,,[12^]"
    }
  }

  func test_bufferingNewest() async {
    validate {
      "X-12-   34    -5|"
      $0.inputs[0].buffer(policy: .bufferingNewest(2))
      "X,,,[1,],,[3,],[4,][5,]|"
    }
  }

  func test_bufferingNewest_noDrops() async {
    validate {
      "X-12   3   4   5   |"
      $0.inputs[0].buffer(policy: .bufferingNewest(2))
      "X,,[1,][2,][3,][45]|"
    }
  }

  func test_bufferingNewest_error() async {
    validate {
      "X-12345^"
      $0.inputs[0].buffer(policy: .bufferingNewest(2))
      "X,,,,,,[45^]"
    }
  }
}

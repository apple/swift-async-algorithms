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

  func test_multi_tasks() async {
    var values = GatedSequence(Array(0 ... 10))
    let bufferSeq = values.buffer(policy: .unbounded)
    var iter_ = bufferSeq.makeAsyncIterator()

    // Initiate the sequence's operation and creation of its Task and actor before sharing its iterator.
    values.advance()
    let _ = await iter_.next()

    let iter = iter_

    let task1 = Task<[Int], Never> {
      var result = [Int]()
      var iter1 = iter
      while let val = await iter1.next() {
        result.append(val)
      }
      return result
    }

    let task2 = Task<[Int], Never> {
      var result = [Int]()
      var iter2 = iter
      while let val = await iter2.next() {
        result.append(val)
      }
      return result
    }

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()
    values.advance()
    values.advance()

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()
    values.advance()
    values.advance()

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()
    values.advance()
    values.advance()
    values.advance()

    let task1Results = await task1.value
    let task2Results = await task2.value

    XCTAssertEqual(task1Results.sorted(), task1Results)
    XCTAssertEqual(task2Results.sorted(), task2Results)

    let combined = (task1Results + task2Results).sorted()
    XCTAssertEqual(combined, Array(1 ... 10))
  }

  func test_multi_tasks_error() async {
    var values = GatedSequence(Array(0 ... 10))
    let mapSeq = values.map { try throwOn(7, $0) }
    let bufferSeq = mapSeq.buffer(policy: .unbounded)
    var iter_ = bufferSeq.makeAsyncIterator()

    // Initiate the sequence's operation and creation of its Task and actor before sharing its iterator.
    values.advance()
    let _ = try! await iter_.next()

    let iter = iter_

    let task1 = Task<([Int], Error?), Never> {
      var result = [Int]()
      var err: Error?
      var iter1 = iter
      do {
        while let val = try await iter1.next() {
          result.append(val)
        }
      } catch {
        err = error
      }
      return (result, err)
    }

    let task2 = Task<([Int], Error?), Never> {
      var result = [Int]()
      var err: Error?
      var iter2 = iter
      do {
        while let val = try await iter2.next() {
          result.append(val)
        }
      } catch {
        err = error
      }
      return (result, err)
    }

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()
    values.advance()
    values.advance()

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()
    values.advance()
    values.advance()

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()

    let task1Results = await task1.value
    let task2Results = await task2.value

    XCTAssertEqual(task1Results.0.sorted(), task1Results.0)
    XCTAssertEqual(task2Results.0.sorted(), task2Results.0)

    let combined = (task1Results.0 + task2Results.0).sorted()
    XCTAssertEqual(combined, Array(1 ... 6))

    XCTAssertEqual(1, [task1Results, task2Results].compactMap{ $0.1 }.count)
  }

  func test_multi_tasks_delegateBufferError() async {
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
          if value == 7 {
            throw Failure()
          }
          return value
        }
        return nil
      }
    }
    let delegate = BufferDelegate()

    var values = GatedSequence(Array(0 ... 10))
    let bufferSeq = values.buffer { delegate }
    var iter_ = bufferSeq.makeAsyncIterator()

    // Initiate the sequence's operation and creation of its Task and actor before sharing its iterator.
    values.advance()
    let _ = try! await iter_.next()

    let iter = iter_

    let task1 = Task<([Int], Error?), Never> {
      var result = [Int]()
      var err: Error?
      var iter1 = iter
      do {
        while let val = try await iter1.next() {
          result.append(val)
        }
      } catch {
        err = error
      }
      return (result, err)
    }

    let task2 = Task<([Int], Error?), Never> {
      var result = [Int]()
      var err: Error?
      var iter2 = iter
      do {
        while let val = try await iter2.next() {
          result.append(val)
        }
      } catch {
        err = error
      }
      return (result, err)
    }

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()
    values.advance()
    values.advance()

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()
    values.advance()
    values.advance()

    try? await Task.sleep(nanoseconds: 100_000_000)
    values.advance()

    let task1Results = await task1.value
    let task2Results = await task2.value

    XCTAssertEqual(task1Results.0.sorted(), task1Results.0)
    XCTAssertEqual(task2Results.0.sorted(), task2Results.0)

    let combined = (task1Results.0 + task2Results.0).sorted()
    XCTAssertEqual(combined, Array(1 ... 6))

    XCTAssertEqual(1, [task1Results, task2Results].compactMap{ $0.1 }.count)
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

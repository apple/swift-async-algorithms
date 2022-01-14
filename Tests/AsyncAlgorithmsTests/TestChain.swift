//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
import AsyncAlgorithms

final class TestChain2: XCTestCase {
  func test_chain() async {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual([1, 2, 3, 4, 5, 6], actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_first() async throws {
    let chained = chain([1, 2, 3].async.map { try throwOn(3, $0) }, [4, 5, 6].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_second() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async.map { try throwOn(5, $0) })
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2, 3, 4], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
}

final class TestChain3: XCTestCase {
  func test_chain() async {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    while let item = await iterator.next() {
      actual.append(item)
    }
    XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8, 9], actual)
    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_first() async throws {
    let chained = chain([1, 2, 3].async.map { try throwOn(3, $0) }, [4, 5, 6].async, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_second() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async.map { try throwOn(5, $0) }, [7, 8, 9].async)
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2, 3, 4], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
  
  func test_throwing_third() async throws {
    let chained = chain([1, 2, 3].async, [4, 5, 6].async, [7, 8, 9].async.map { try throwOn(8, $0) })
    var iterator = chained.makeAsyncIterator()
    var actual = [Int]()
    do {
      while let item = try await iterator.next() {
        actual.append(item)
      }
      XCTFail()
    } catch {
      XCTAssertEqual(Failure(), error as? Failure)
    }
    XCTAssertEqual([1, 2, 3, 4, 5, 6, 7], actual)
    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }
}

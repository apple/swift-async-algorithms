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

@available(AsyncAlgorithms 1.2, *)
struct FailingSequence<Failure: Error>: AsyncSequence, Sendable {
  typealias Element = Void
  let error: Failure
  init(_ error: Failure) {
    self.error = error
  }
  func makeAsyncIterator() -> AsyncIterator { AsyncIterator(error: error) }
  
  struct AsyncIterator: AsyncIteratorProtocol, Sendable {
    let error: Failure
    func next() async throws(Failure) -> Void? {
      throw error
    }
    mutating func next(completion: @escaping (Result<Element?, Failure>) -> Void) async throws(Failure) -> Element? {
      throw error
    }
  }
}

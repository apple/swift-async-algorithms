//
//  FailingSequence.swift
//  swift-async-algorithms
//
//  Created by Stefano Mondino on 15/10/25.
//

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

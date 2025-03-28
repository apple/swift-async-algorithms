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

extension AsyncSequence {
  func violatingSpecification(returningPastEndIteration element: Element) -> SpecificationViolatingSequence<Self> {
    SpecificationViolatingSequence(self, kind: .producing(element))
  }

  func violatingSpecification(throwingPastEndIteration error: Error) -> SpecificationViolatingSequence<Self> {
    SpecificationViolatingSequence(self, kind: .throwing(error))
  }
}

struct SpecificationViolatingSequence<Base: AsyncSequence> {
  enum Kind {
    case producing(Base.Element)
    case throwing(Error)
  }

  let base: Base
  let kind: Kind

  init(_ base: Base, kind: Kind) {
    self.base = base
    self.kind = kind
  }
}

extension SpecificationViolatingSequence: AsyncSequence {
  typealias Element = Base.Element

  struct Iterator: AsyncIteratorProtocol {
    var iterator: Base.AsyncIterator
    let kind: Kind
    var finished = false
    var violated = false

    mutating func next() async throws -> Element? {
      if finished {
        if violated {
          return nil
        }
        violated = true
        switch kind {
        case .producing(let element): return element
        case .throwing(let error): throw error
        }
      }
      do {
        if let value = try await iterator.next() {
          return value
        }
        finished = true
        return nil
      } catch {
        finished = true
        throw error
      }
    }
  }

  func makeAsyncIterator() -> Iterator {
    Iterator(iterator: base.makeAsyncIterator(), kind: kind)
  }
}

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

public struct GatedSequence<Element> {
  public typealias Failure = Never
  let elements: [Element]
  let gates: [Gate]
  var index = 0

  public mutating func advance() {
    defer { index += 1 }
    guard index < gates.count else {
      return
    }
    gates[index].open()
  }

  public init(_ elements: [Element]) {
    self.elements = elements
    self.gates = elements.map { _ in Gate() }
  }
}

extension GatedSequence: AsyncSequence {
  public struct Iterator: AsyncIteratorProtocol {
    var gatedElements: [(Element, Gate)]

    init(elements: [Element], gates: [Gate]) {
      gatedElements = Array(zip(elements, gates))
    }

    public mutating func next() async -> Element? {
      guard gatedElements.count > 0 else {
        return nil
      }
      let (element, gate) = gatedElements.removeFirst()
      await gate.enter()
      return element
    }

    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Never) -> Element? {
      guard gatedElements.count > 0 else {
        return nil
      }
      let (element, gate) = gatedElements.removeFirst()
      await gate.enter()
      return element
    }
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(elements: elements, gates: gates)
  }
}

extension GatedSequence: Sendable where Element: Sendable {}

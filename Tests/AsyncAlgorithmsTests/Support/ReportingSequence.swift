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

final class ReportingSequence<Element>: Sequence, IteratorProtocol {
  enum Event: Equatable, CustomStringConvertible {
    case next
    case makeIterator

    var description: String {
      switch self {
      case .next: return "next()"
      case .makeIterator: return "makeIterator()"
      }
    }
  }

  var events = [Event]()
  var elements: [Element]

  init(_ elements: [Element]) {
    self.elements = elements
  }

  func next() -> Element? {
    events.append(.next)
    guard elements.count > 0 else {
      return nil
    }
    return elements.removeFirst()
  }

  func makeIterator() -> ReportingSequence {
    events.append(.makeIterator)
    return self
  }
}

final class ReportingAsyncSequence<Element: Sendable>: AsyncSequence, AsyncIteratorProtocol, @unchecked Sendable {
  enum Event: Equatable, CustomStringConvertible {
    case next
    case makeAsyncIterator

    var description: String {
      switch self {
      case .next: return "next()"
      case .makeAsyncIterator: return "makeAsyncIterator()"
      }
    }
  }

  var events = [Event]()
  var elements: [Element]

  init(_ elements: [Element]) {
    self.elements = elements
  }

  func next() async -> Element? {
    events.append(.next)
    guard elements.count > 0 else {
      return nil
    }
    return elements.removeFirst()
  }

  func makeAsyncIterator() -> ReportingAsyncSequence {
    events.append(.makeAsyncIterator)
    return self
  }
}

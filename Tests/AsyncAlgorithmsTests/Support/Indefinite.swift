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

struct Indefinite<Element: Sendable>: Sequence, IteratorProtocol, Sendable {
  let value: Element

  func next() -> Element? {
    return value
  }

  func makeIterator() -> Indefinite<Element> {
    self
  }
}

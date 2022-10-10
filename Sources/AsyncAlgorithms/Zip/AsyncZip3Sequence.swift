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

/// Creates an asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
public func zip<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2,
  _ base3: Base3
) -> AsyncZip3Sequence<Base1, Base2, Base3> {
  AsyncZip3Sequence(base1, base2, base3)
}

/// An asynchronous sequence that concurrently awaits values from three `AsyncSequence` types
/// and emits a tuple of the values.
public struct AsyncZip3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: AsyncSequence
where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable, Base3: Sendable, Base3.Element: Sendable {
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2
  let base3: Base3

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base1,
      base2,
      base3
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let runtime: Zip3Runtime<Base1, Base2, Base3>

    init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
      self.runtime = Zip3Runtime(base1, base2, base3)
    }

    public mutating func next() async rethrows -> Element? {
      try await self.runtime.next()
    }
  }
}

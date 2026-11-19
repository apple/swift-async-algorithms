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

public extension AsyncSequence {
  func broadcast() -> AsyncBroadcastSequence<Self> {
    AsyncBroadcastSequence(base: self)
  }
}

public struct AsyncBroadcastSequence<Base: AsyncSequence>: AsyncSequence where Base: Sendable, Base.Element: Sendable {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  private let storage: BroadcastStorage<Base>

  public init(base: Base) {
    self.storage = BroadcastStorage(base: base)
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(storage: self.storage)
  }

  public struct Iterator: AsyncIteratorProtocol {
    private var id: Int
    private let storage: BroadcastStorage<Base>

    init(storage: BroadcastStorage<Base>) {
      self.storage = storage
      self.id = storage.generateId()
    }

    public mutating func next() async rethrows -> Element? {
      let element = await self.storage.next(id: self.id)
      return try element?._rethrowGet()
    }
  }
}

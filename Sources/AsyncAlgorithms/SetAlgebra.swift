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

@available(AsyncAlgorithms 1.0, *)
extension SetAlgebra {
  /// Creates a new set from an asynchronous sequence of items.
  ///
  /// Use this initializer to create a new set from an asynchronous sequence
  ///
  /// - Parameter source: The elements to use as members of the new set.
  @inlinable
  public init<Source: AsyncSequence>(_ source: Source) async rethrows where Source.Element == Element {
    self.init()
    for try await item in source {
      insert(item)
    }
  }
}

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

extension RangeReplaceableCollection {
  public init<Source: AsyncSequence>(_ source: Source) async rethrows where Source.Element == Element {
    self.init()
    for try await item in source {
      append(item)
    }
  }
}

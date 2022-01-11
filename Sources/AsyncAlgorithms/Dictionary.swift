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

extension Dictionary {
  public init<S: AsyncSequence>(uniqueKeysWithValues keysAndValues: S) async rethrows where S.Element == (Key, Value)  {
    self.init(uniqueKeysWithValues: try await Array(keysAndValues))
  }
  
  public init<S: AsyncSequence>(_ keysAndValues: S, uniquingKeysWith combine: (Value, Value) async throws -> Value) async rethrows where S.Element == (Key, Value) {
    self.init()
    for try await (key, value) in keysAndValues {
      if let existing = self[key] {
        self[key] = try await combine(existing, value)
      } else {
        self[key] = value
      }
    }
  }
  
  public init<S: AsyncSequence>(grouping values: S, by keyForValue: (S.Element) async throws -> Key) async rethrows where Value == [S.Element] {
    self.init()
    for try await value in values {
      let key = try await keyForValue(value)
      self[key, default: []].append(value)
    }
  }
}

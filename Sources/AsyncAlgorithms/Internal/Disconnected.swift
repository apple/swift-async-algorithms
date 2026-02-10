//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.1)
// This is a helper type to move a non-Sendable value across isolation regions.
@usableFromInline
struct Disconnected<Value: ~Copyable>: ~Copyable, Sendable {
  // This is safe since we take the value as sending and take consumes it
  // and returns it as sending.
  private nonisolated(unsafe) var value: Value?

  @usableFromInline
  init(value: consuming sending Value) {
    self.value = .some(value)
  }

  @usableFromInline
  consuming func take() -> sending Value {
    nonisolated(unsafe) let value = self.value.take()!
    return value
  }

  @usableFromInline
  mutating func swap(newValue: consuming sending Value) -> sending Value {
    nonisolated(unsafe) let value = self.value.take()!
    self.value = consume newValue
    return value
  }
}
#endif

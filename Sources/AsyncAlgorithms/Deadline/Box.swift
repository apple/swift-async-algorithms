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

#if compiler(>=6.2)
// A helper to box a ~Copyable type in a referenced counted class
final class RefBox<Value: ~Copyable> {
  private nonisolated(unsafe) var value: Value?

  init(value: consuming Value) {
    self.value = consume value
  }

  consuming func unbox() -> Value {
    return value.take()!
  }
}

extension RefBox: Sendable where Value: Sendable & ~Copyable {}
#endif

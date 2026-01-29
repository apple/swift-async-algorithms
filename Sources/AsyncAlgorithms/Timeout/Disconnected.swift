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

#if compiler(>=6.2)
// This is a helper type to move a non-Sendable value across isolation regions.
struct Disconnected<Value>: Sendable {
  // This is safe since we take the value as sending and take consumes it
  // and returns it as sending.
  private nonisolated(unsafe) var value: Value?

  init(value: consuming sending Value) {
    self.value = .some(value)
  }

  consuming func take() -> sending Value {
    self.value.takeSending()!
  }
}
#endif

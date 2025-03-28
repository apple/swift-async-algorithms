//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A wrapper struct to unconditionally to transfer an non-Sendable value.
struct UnsafeTransfer<Element>: @unchecked Sendable {
  let wrapped: Element

  init(_ wrapped: Element) {
    self.wrapped = wrapped
  }
}

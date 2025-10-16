//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// Backportable versions of `sleep(for:)` for legacy platforms where this kind of method is not available
extension Task where Success == Never, Failure == Never {
  
  static func sleep(milliseconds duration: UInt64) async throws {
    try await sleep(duration, multiplier: 1_000_000)
  }
  static func sleep(microseconds duration: UInt64) async throws {
    try await sleep(duration, multiplier: 1_000)
  }
  static func sleep(seconds duration: UInt64) async throws {
    try await sleep(duration, multiplier: 1_000_000_000)
  }
  
  private static func sleep(_ value: UInt64, multiplier: UInt64) async throws {
    guard UInt64.max / multiplier > value else {
      throw SleepError.durationOutOfBounds
    }
    try await sleep(nanoseconds: value * multiplier)
  }
}

fileprivate enum SleepError: Error {
  case durationOutOfBounds
}

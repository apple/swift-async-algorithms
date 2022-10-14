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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct TimeoutError<C: Clock>: Error {
  public let deadline: C.Instant
  public let clock: C
  
  public init(_ deadline: C.Instant, _ clock: C) {
    self.deadline = deadline
    self.clock = clock
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func withDeadline<C: Clock, T: Sendable>(
  _ deadline: C.Instant,
  clock: C,
  _ operation: @Sendable () async throws -> T
) async throws -> T {
  return try await withoutActuallyEscaping(operation) { operation in
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask(operation: operation)
      group.addTask {
        try await Task.sleep(until: deadline, clock: clock)
        throw TimeoutError(deadline, clock)
      }
      defer { group.cancelAll() }
      return try await group.next()!
    }
  }
}

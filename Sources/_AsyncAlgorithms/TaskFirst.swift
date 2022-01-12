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

import Swift
import _Concurrency

struct ContinuationContainer<Success, Failure: Error>: Sendable {
  final class Contents: @unchecked Sendable {
    var continuationPointer:
      UnsafeMutablePointer<UnsafeContinuation<Success, Failure>?> {
      let tail = Builtin.projectTailElems(self,
        UnsafeContinuation<Success, Failure>?.self)
      return UnsafeMutablePointer(tail)
    }
  }
  
  let contents: Contents
  
  static func create(
    _ continuation: UnsafeContinuation<Success, Failure>
  ) -> ContinuationContainer {
    let container = Builtin.allocWithTailElems_1(
      Contents.self,
      1._builtinWordValue,
      UnsafeContinuation<Success, Failure>?.self)
    container.continuationPointer.initialize(to: continuation)
    return ContinuationContainer(contents: container)
  }
  
  func resume<Er: Error>(
    with result: Result<Success, Er>
  ) where Failure == Error {
    let raw = Builtin.atomicrmw_xchg_acqrel_Word(
      unsafeBitCast(contents.continuationPointer, to: Builtin.RawPointer.self),
      UInt(bitPattern: 0)._builtinWordValue
    )
    let continuation = unsafeBitCast(raw, to:
      UnsafeContinuation<Success, Failure>?.self)
    continuation?.resume(with: result)
  }
  
  func resume(
    with result: Result<Success, Failure>
  ) where Failure == Never {
    let raw = Builtin.atomicrmw_xchg_acqrel_Word(
      unsafeBitCast(contents.continuationPointer, to: Builtin.RawPointer.self),
      UInt(bitPattern: 0)._builtinWordValue
    )
    let continuation = unsafeBitCast(raw, to:
      UnsafeContinuation<Success, Failure>?.self)
    continuation?.resume(with: result)
  }
}

extension Task {
  /// Determine the first result of a sequence of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first result or thrown error from the running tasks
  public static func first<Tasks: Sequence>(
    _ tasks: Tasks
  ) async throws -> Success
  where Tasks.Element == Task<Success, Failure> {
    return try await withUnsafeThrowingContinuation { continuation in
      let container = ContinuationContainer.create(continuation)
      for task in tasks {
        Task<Void, Never> {
          let result = await task.result
          container.resume(with: result)
        }
      }
    }
  }
  
  /// Determine the first result of a list of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first result or thrown error from the running tasks
  public static func first(
    _ tasks: Task<Success, Failure>...
  ) async throws -> Success {
    try await first(tasks)
  }
}

extension Task where Failure == Never {
  /// Determine the first result of a sequence of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first result from the running tasks
  public static func first<Tasks: Sequence>(
    _ tasks: Tasks
  ) async -> Success
  where Tasks.Element == Task<Success, Never> {
    return await withUnsafeContinuation { continuation in
      let container = ContinuationContainer.create(continuation)
      for task in tasks {
        Task<Void, Never> {
          let result = await task.result
          container.resume(with: result)
        }
      }
    }
  }

  /// Determine the first result of a list of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first result from the running tasks
  public static func first(
    _ tasks: Task<Success, Never>...
  ) async -> Success {
    await first(tasks)
  }
}

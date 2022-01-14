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

struct TaskFirstState<Success: Sendable, Failure: Error>: Sendable {
  var continuation: UnsafeContinuation<Success, Failure>?
  var tasks: [Task<Success, Failure>]? = []
  
  mutating func add(_ task: Task<Success, Failure>) -> Task<Success, Failure>? {
    if var tasks = tasks {
      tasks.append(task)
      self.tasks = tasks
      return nil
    } else {
      return task
    }
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
  where Tasks.Element == Task<Success, Failure>, Failure == Error {
    let state = ManagedCriticalState(TaskFirstState<Success, Failure>())
    return try await withTaskCancellationHandler {
      let tasks = state.withCriticalRegion { state -> [Task<Success, Failure>] in
        defer { state.tasks = nil }
        return state.tasks ?? []
      }
      for task in tasks {
        task.cancel()
      }
    } operation: {
      try await withUnsafeThrowingContinuation { continuation in
        state.withCriticalRegion { state in
          state.continuation = continuation
        }
        for task in tasks {
          Task<Void, Never> {
            let result = await task.result
            state.withCriticalRegion { state -> UnsafeContinuation<Success, Failure>? in
              defer { state.continuation = nil }
              return state.continuation
            }?.resume(with: result)
          }
          state.withCriticalRegion { state in
            state.add(task)
          }?.cancel()
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
  ) async throws -> Success where Failure == Error {
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
    let state = ManagedCriticalState(TaskFirstState<Success, Failure>())
    return await withTaskCancellationHandler {
      let tasks = state.withCriticalRegion { state -> [Task<Success, Failure>] in
        defer { state.tasks = nil }
        return state.tasks ?? []
      }
      for task in tasks {
        task.cancel()
      }
    } operation: {
      await withUnsafeContinuation { continuation in
        state.withCriticalRegion { state in
          state.continuation = continuation
        }
        for task in tasks {
          Task<Void, Never> {
            let result = await task.result
            state.withCriticalRegion { state -> UnsafeContinuation<Success, Failure>? in
              defer { state.continuation = nil }
              return state.continuation
            }?.resume(with: result)
          }
          state.withCriticalRegion { state in
            state.add(task)
          }?.cancel()
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

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

struct TaskSelectState<Success: Sendable, Failure: Error>: Sendable {
  var complete = false
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
  /// Determine the first task to complete of a sequence of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first task to complete from the running tasks
  public static func select<Tasks: Sequence & Sendable>(
    _ tasks: Tasks
  ) async -> Task<Success, Failure>
  where Tasks.Element == Task<Success, Failure> {
    let state = ManagedCriticalState(TaskSelectState<Success, Failure>())
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
        for task in tasks {
          Task<Void, Never> {
            _ = await task.result
            let winner = state.withCriticalRegion { state -> Bool in
              defer { state.complete = true }
              return !state.complete
            }
            if winner {
              continuation.resume(returning: task)
            }
          }
          state.withCriticalRegion { state in
            state.add(task)
          }?.cancel()
        }
      }
    }
  }
  
  /// Determine the first task to complete of a list of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first task to complete from the running tasks
  public static func select(
    _ tasks: Task<Success, Failure>...
  ) async -> Task<Success, Failure> {
    await select(tasks)
  }
}


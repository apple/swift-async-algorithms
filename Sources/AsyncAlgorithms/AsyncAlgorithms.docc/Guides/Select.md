# Task.select

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/TaskSelect.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestTaskSelect.swift)
]

## Introduction

A fundamental part of many algorithms is being able to select the first resolved task from a given list of active tasks. This enables algorithms like `debounce` or `merge`. 

## Proposed Solution

Selecting the first task to complete from a list of active tasks is a similar algorithm to `select(2)`. This has similar behavior to `TaskGroup` except that instead of child tasks this function transacts upon already running tasks and does not cancel them upon completion of the selection and does not need to await for the completion of all of the tasks in the list to select. 

```swift
extension Task {
  public static func select<Tasks: Sequence & Sendable>(
    _ tasks: Tasks
  ) async -> Task<Success, Failure>
  
  public static func select(
    _ tasks: Task<Success, Failure>...
  ) async -> Task<Success, Failure>
}
```

## Detailed Design

Given any number of `Task` objects that share the same `Success` and `Failure` types; `Task.select` will suspend and await each tasks result and resume when the first task has produced a result. While the calling task of `Task.select` is suspended if that task is cancelled the tasks being selected receive the cancel. This is similar to the family of `TaskGroup` with a few behavioral and structural differences. 

The `withTaskGroup` API will create efficient child tasks.
The `Task.select` API takes pre-existing tasks.

The `withTaskGroup` API will await all child tasks to be finished before returning. 
The `Task.select` API will await for the first task to be finished before returning.

The `withTaskGroup` API will cancel all outstanding child tasks upon awaiting its return.
The `Task.select` API will let the non selected tasks keep on running.

The `withTaskGroup` can support having 0 child tasks.
The `Task.select` API requires at least 1 task to select over, anything less is a programmer error. 

This means that `withTaskGroup` is highly suited to run work in parallel, whereas `Task.select` is intended to find the first task that provides a value. There is inherent additional cost to the non-child tasks so `Task.select` should not be used as a replacement for anywhere that is more suitable as a group, but offers more potential for advanced algorithms.

## Alternatives Considered

## Future Directions


## Credits/Inspiration

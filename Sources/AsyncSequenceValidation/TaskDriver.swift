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

import _CAsyncSequenceValidationSupport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#elseif canImport(wasi_pthread)
import wasi_pthread
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#else
#error("Unsupported platform")
#endif

#if canImport(Darwin)
@available(AsyncAlgorithms 1.0, *)
func start_thread(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  Unmanaged<TaskDriver>.fromOpaque(raw).takeRetainedValue().run()
  return nil
}
#elseif (canImport(Glibc) && !os(Android)) || canImport(Musl) || canImport(wasi_pthread)
@available(AsyncAlgorithms 1.0, *)
func start_thread(_ raw: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
  Unmanaged<TaskDriver>.fromOpaque(raw!).takeRetainedValue().run()
  return nil
}
#elseif os(Android)
@available(AsyncAlgorithms 1.0, *)
func start_thread(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
  Unmanaged<TaskDriver>.fromOpaque(raw).takeRetainedValue().run()
  return UnsafeMutableRawPointer(bitPattern: 0xdeadbee)!
}
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif

@available(AsyncAlgorithms 1.0, *)
final class TaskDriver: Sendable {
  let work: @Sendable (TaskDriver) -> Void
  let queue: WorkQueue
  #if canImport(Darwin) || canImport(wasi_pthread)
  nonisolated(unsafe) var thread: pthread_t?
  #elseif canImport(Glibc) || canImport(Musl) || canImport(Bionic)
  nonisolated(unsafe) var thread = pthread_t()
  #elseif canImport(WinSDK)
  #error("TODO: Port TaskDriver threading to windows")
  #endif

  init(queue: WorkQueue, _ work: @Sendable @escaping (TaskDriver) -> Void) {
    self.queue = queue
    self.work = work
  }

  func start() {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Bionic) || canImport(wasi_pthread)
    pthread_create(
      &thread,
      nil,
      start_thread,
      Unmanaged.passRetained(self).toOpaque()
    )
    #elseif canImport(WinSDK)
    #error("TODO: Port TaskDriver threading to windows")
    #endif
  }

  func run() {
    #if canImport(Darwin)
    pthread_setname_np("Validation Diagram Clock Driver")
    #endif
    work(self)
  }

  func join() {
    #if canImport(Darwin) || canImport(wasi_pthread)
    pthread_join(thread!, nil)
    #elseif canImport(Glibc) || canImport(Musl) || canImport(Bionic)
    pthread_join(thread, nil)
    #elseif canImport(WinSDK)
    #error("TODO: Port TaskDriver threading to windows")
    #endif
  }

  func enqueue(_ job: JobRef) {
    let job = Job(job)
    queue.enqueue(AsyncSequenceValidationDiagram.Context.currentJob) {
      let previous = AsyncSequenceValidationDiagram.Context.currentJob
      AsyncSequenceValidationDiagram.Context.currentJob = job
      job.execute()
      AsyncSequenceValidationDiagram.Context.currentJob = previous
    }
  }
}

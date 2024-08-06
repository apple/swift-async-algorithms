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
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#else
#error("Unsupported platform")
#endif

#if canImport(Darwin)
func start_thread(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  Unmanaged<TaskDriver>.fromOpaque(raw).takeRetainedValue().run()
  return nil
}
#elseif canImport(Glibc) || canImport(Musl)
func start_thread(_ raw: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
  Unmanaged<TaskDriver>.fromOpaque(raw!).takeRetainedValue().run()
  return nil
}
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif

final class TaskDriver {
  let work: (TaskDriver) -> Void
  let queue: WorkQueue
#if canImport(Darwin)
  var thread: pthread_t?
#elseif canImport(Glibc) || canImport(Musl)
  var thread = pthread_t()
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif
  
  init(queue: WorkQueue, _ work: @escaping (TaskDriver) -> Void) {
    self.queue = queue
    self.work = work
  }
  
  func start() {
#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
    pthread_create(&thread, nil, start_thread,
      Unmanaged.passRetained(self).toOpaque())
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
#if canImport(Darwin)
    pthread_join(thread!, nil)
#elseif canImport(Glibc) || canImport(Musl)
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


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
@_implementationOnly import Darwin
#elseif canImport(Glibc)
@_implementationOnly import Glibc
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif

func start_thread(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  Unmanaged<TaskDriver>.fromOpaque(raw).takeRetainedValue().run()
  return nil
}

final class TaskDriver {
  let work: (TaskDriver) -> Void
  let queue: WorkQueue
  var thread: pthread_t?
  
  init(queue: WorkQueue, _ work: @escaping (TaskDriver) -> Void) {
    self.queue = queue
    self.work = work
  }
  
  func start() {
    pthread_create(&thread, nil, start_thread,
      Unmanaged.passRetained(self).toOpaque())
  }
  
  func run() {
    pthread_setname_np("Validation Diagram Clock Driver")
    work(self)
  }
  
  func join() {
    pthread_join(thread!, nil)
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


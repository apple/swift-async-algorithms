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
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif

final class TaskDriver: @unchecked Sendable {
  let work: @Sendable (TaskDriver) -> Void
  let queue: WorkQueue
#if canImport(Darwin)
  var thread: pthread_t?
#elseif canImport(Glibc)
  var thread = pthread_t()
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif

  private let lock = Lock.allocate()

  init(queue: WorkQueue, _ work: @Sendable @escaping (TaskDriver) -> Void) {
    self.queue = queue
    self.work = work
  }
  
  func start() {
#if canImport(Darwin)
    func start_thread(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
      Unmanaged<TaskDriver>.fromOpaque(raw).takeRetainedValue().run()
      return nil
    }
#elseif canImport(Glibc)
    func start_thread(_ raw: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
      Unmanaged<TaskDriver>.fromOpaque(raw!).takeRetainedValue().run()
      return nil
    }
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif

    lock.withLockVoid {
#if canImport(Darwin) || canImport(Glibc)
      pthread_create(&thread, nil, start_thread,
                     Unmanaged.passRetained(self).toOpaque())
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif
    }
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
#elseif canImport(Glibc)
    pthread_join(thread, nil)
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif
  }
  
  func enqueue(_ job: JobRef) {
    let job = Job(job)
    queue.enqueue(AsyncSequenceValidationDiagram.Context.state.withCriticalRegion(\.currentJob)) {
      let previous = AsyncSequenceValidationDiagram.Context.state.withCriticalRegion(\.currentJob)
      AsyncSequenceValidationDiagram.Context.state.withCriticalRegion { $0.currentJob = job }
      job.execute()
      AsyncSequenceValidationDiagram.Context.state.withCriticalRegion { $0.currentJob = previous }
    }
  }
}


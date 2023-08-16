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

#if canImport(Darwin)
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
func start_thread(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  Unmanaged<TaskDriver>.fromOpaque(raw).takeRetainedValue().run()
  return nil
}
#elseif canImport(Glibc)
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
func start_thread(_ raw: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
  Unmanaged<TaskDriver>.fromOpaque(raw!).takeRetainedValue().run()
  return nil
}
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class TaskDriver {
  let work: (TaskDriver) -> Void
  let queue: WorkQueue
#if canImport(Darwin)
  var thread: pthread_t?
#elseif canImport(Glibc)
  var thread = pthread_t()
#elseif canImport(WinSDK)
#error("TODO: Port TaskDriver threading to windows")
#endif
  
  init(queue: WorkQueue, _ work: @escaping (TaskDriver) -> Void) {
    self.queue = queue
    self.work = work
  }
  
  func start() {
#if canImport(Darwin) || canImport(Glibc)
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
#elseif canImport(Glibc)
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


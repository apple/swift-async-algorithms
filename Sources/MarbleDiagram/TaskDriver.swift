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

import CMarableDiagram

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
  struct State {
    var queue = [() -> Void]()
    var executing = false
  }
  
  let work: (TaskDriver) -> Void
  var thread: pthread_t?
  let state = ManagedCriticalState(State())
  
  init(_ work: @escaping (TaskDriver) -> Void) {
    self.work = work
  }
  
  func start() {
    pthread_create(&thread, nil, start_thread,
      Unmanaged.passRetained(self).toOpaque())
  }
  
  func run() {
    pthread_setname_np("Marble Diagram Clock Driver")
    work(self)
  }
  
  func join() {
    pthread_join(thread!, nil)
  }
  
  func enqueue(_ job: JobRef, _ execute: @escaping () -> Void) {
    state.withCriticalRegion { state in
      state.queue.append(execute)
    }
  }
  
  func drain() -> Bool {
    let items: [() -> Void] = state.withCriticalRegion { state in
      defer { state.queue.removeAll() }
      state.executing = true
      return state.queue
    }
    
    for item in items {
      item()
    }
    
    return state.withCriticalRegion { state in
      state.executing = false
      return state.queue.count > 0
    }
  }
}


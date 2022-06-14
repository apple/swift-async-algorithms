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

#if canImport(Darwin)
@_implementationOnly import Darwin
#elseif canImport(Glibc)
@_implementationOnly import Glibc
#elseif canImport(WinSDK)
@_implementationOnly import WinSDK
#endif

private final class Lock {
#if canImport(Darwin)
  typealias Primitive = os_unfair_lock
#elseif canImport(Glibc)
  typealias Primitive = pthread_mutex_t
#elseif canImport(WinSDK)
  typealias Primitive = SRWLOCK
#endif

  private let _lock: UnsafeMutablePointer<Primitive>

  init() {
    _lock = UnsafeMutablePointer<Primitive>.allocate(capacity: 1)
#if canImport(Darwin)
    _lock.initialize(to: os_unfair_lock())
#elseif canImport(Glibc)
    pthread_mutex_init(_lock, nil)
#elseif canImport(WinSDK)
    InitializeSRWLock(_lock)
#endif
  }

  deinit {
#if canImport(Glibc)
    pthread_mutex_destroy(_lock)
#endif
    _lock.deinitialize(count: 1)
    _lock.deallocate()
  }

  func lock() {
#if canImport(Darwin)
    os_unfair_lock_lock(_lock)
#elseif canImport(Glibc)
    pthread_mutex_lock(_lock)
#elseif canImport(WinSDK)
    AcquireSRWLockExclusive(_lock)
#endif
  }

  func unlock() {
#if canImport(Darwin)
    os_unfair_lock_unlock(_lock)
#elseif canImport(Glibc)
    pthread_mutex_unlock(_lock)
#elseif canImport(WinSDK)
    ReleaseSRWLockExclusive(_lock)
#endif
  }
}

final class ManagedCriticalState<State> {  
  private let _lock = Lock()
  private var _state: State
  
  init(_ initial: State) {
    _state = initial
  }
  
  func withCriticalRegion<R>(_ critical: (inout State) throws -> R) rethrows -> R {
    Lock.lock(lock)
    defer { Lock.unlock(lock) }
    return try critical(&_state)
  }
}

extension ManagedCriticalState: @unchecked Sendable where State: Sendable { }

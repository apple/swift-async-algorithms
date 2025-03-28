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

import AsyncAlgorithms

public struct ManualClock: Clock {
  public struct Step: DurationProtocol {
    fileprivate var rawValue: Int

    fileprivate init(_ rawValue: Int) {
      self.rawValue = rawValue
    }

    public static func + (lhs: ManualClock.Step, rhs: ManualClock.Step) -> ManualClock.Step {
      return .init(lhs.rawValue + rhs.rawValue)
    }

    public static func - (lhs: ManualClock.Step, rhs: ManualClock.Step) -> ManualClock.Step {
      .init(lhs.rawValue - rhs.rawValue)
    }

    public static func / (lhs: ManualClock.Step, rhs: Int) -> ManualClock.Step {
      .init(lhs.rawValue / rhs)
    }

    public static func * (lhs: ManualClock.Step, rhs: Int) -> ManualClock.Step {
      .init(lhs.rawValue * rhs)
    }

    public static func / (lhs: ManualClock.Step, rhs: ManualClock.Step) -> Double {
      Double(lhs.rawValue) / Double(rhs.rawValue)
    }

    public static func < (lhs: ManualClock.Step, rhs: ManualClock.Step) -> Bool {
      lhs.rawValue < rhs.rawValue
    }

    public static var zero: ManualClock.Step { .init(0) }

    public static func steps(_ amount: Int) -> Step {
      return Step(amount)
    }
  }

  public struct Instant: InstantProtocol, CustomStringConvertible {
    public typealias Duration = Step

    internal let rawValue: Int

    internal init(_ rawValue: Int) {
      self.rawValue = rawValue
    }

    public static func < (lhs: ManualClock.Instant, rhs: ManualClock.Instant) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }

    public func advanced(by duration: ManualClock.Step) -> ManualClock.Instant {
      .init(rawValue + duration.rawValue)
    }

    public func duration(to other: ManualClock.Instant) -> ManualClock.Step {
      .init(other.rawValue - rawValue)
    }

    public var description: String {
      return "tick \(rawValue)"
    }
  }

  fileprivate struct Wakeup {
    let generation: Int
    let continuation: UnsafeContinuation<Void, Error>
    let deadline: Instant
  }

  fileprivate enum Scheduled: Hashable, Comparable, CustomStringConvertible {
    case cancelled(Int)
    case wakeup(Wakeup)

    func hash(into hasher: inout Hasher) {
      switch self {
      case .cancelled(let generation):
        hasher.combine(generation)
      case .wakeup(let wakeup):
        hasher.combine(wakeup.generation)
      }
    }

    var description: String {
      switch self {
      case .cancelled: return "Cancelled wakeup"
      case .wakeup(let wakeup): return "Wakeup at \(wakeup.deadline)"
      }
    }

    static func == (_ lhs: Scheduled, _ rhs: Scheduled) -> Bool {
      switch (lhs, rhs) {
      case (.cancelled(let lhsGen), .cancelled(let rhsGen)):
        return lhsGen == rhsGen
      case (.cancelled(let lhsGen), .wakeup(let rhs)):
        return lhsGen == rhs.generation
      case (.wakeup(let lhs), .cancelled(let rhsGen)):
        return lhs.generation == rhsGen
      case (.wakeup(let lhs), .wakeup(let rhs)):
        return lhs.generation == rhs.generation
      }
    }

    static func < (lhs: ManualClock.Scheduled, rhs: ManualClock.Scheduled) -> Bool {
      switch (lhs, rhs) {
      case (.cancelled(let lhsGen), .cancelled(let rhsGen)):
        return lhsGen < rhsGen
      case (.cancelled(let lhsGen), .wakeup(let rhs)):
        return lhsGen < rhs.generation
      case (.wakeup(let lhs), .cancelled(let rhsGen)):
        return lhs.generation < rhsGen
      case (.wakeup(let lhs), .wakeup(let rhs)):
        return lhs.generation < rhs.generation
      }
    }

    var deadline: Instant? {
      switch self {
      case .cancelled: return nil
      case .wakeup(let wakeup): return wakeup.deadline
      }
    }

    func resume() {
      switch self {
      case .wakeup(let wakeup):
        wakeup.continuation.resume()
      default:
        break
      }
    }
  }

  fileprivate struct State {
    var generation = 0
    var scheduled = Set<Scheduled>()
    var now = Instant(0)
    var hasSleepers = false
  }

  fileprivate let state = ManagedCriticalState(State())

  public var now: Instant {
    state.withCriticalRegion { $0.now }
  }

  public var minimumResolution: Step { return .zero }

  public init() {}

  fileprivate func cancel(_ generation: Int) {
    state.withCriticalRegion { state -> UnsafeContinuation<Void, Error>? in
      guard let existing = state.scheduled.remove(.cancelled(generation)) else {
        // insert the cancelled state for when it comes in to be scheduled as a wakeup
        state.scheduled.insert(.cancelled(generation))
        return nil
      }
      switch existing {
      case .wakeup(let wakeup):
        return wakeup.continuation
      default:
        return nil
      }
    }?.resume(throwing: CancellationError())
  }

  var hasSleepers: Bool {
    state.withCriticalRegion { $0.hasSleepers }
  }

  public func advance() {
    let pending = state.withCriticalRegion { state -> Set<Scheduled> in
      state.now = state.now.advanced(by: .steps(1))
      let pending = state.scheduled.filter { item in
        guard let deadline = item.deadline else {
          return false
        }
        return deadline <= state.now
      }
      state.scheduled.subtract(pending)
      if pending.count > 0 {
        state.hasSleepers = false
      }
      return pending
    }
    for item in pending.sorted() {
      item.resume()
    }
  }

  public func advance(by steps: Step) {
    for _ in 0..<steps.rawValue {
      advance()
    }
  }

  fileprivate func schedule(_ generation: Int, continuation: UnsafeContinuation<Void, Error>, deadline: Instant) {
    let resumption = state.withCriticalRegion { state -> (UnsafeContinuation<Void, Error>, Result<Void, Error>)? in
      let wakeup = Wakeup(generation: generation, continuation: continuation, deadline: deadline)
      guard let existing = state.scheduled.remove(.wakeup(wakeup)) else {
        // there is no cancelled placeholder so let it run free
        guard deadline > state.now else {
          // the deadline is now or in the past so run it immediately
          return (continuation, .success(()))
        }
        // the deadline is in the future so run it then
        state.hasSleepers = true
        state.scheduled.insert(.wakeup(wakeup))
        return nil
      }
      switch existing {
      case .wakeup:
        fatalError()
      case .cancelled:
        // dont bother adding it back because it has been cancelled before we got here
        return (continuation, .failure(CancellationError()))
      }
    }
    if let resumption = resumption {
      resumption.0.resume(with: resumption.1)
    }
  }

  public func sleep(until deadline: Instant, tolerance: Step? = nil) async throws {
    let generation = state.withCriticalRegion { state -> Int in
      defer { state.generation += 1 }
      return state.generation
    }
    try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { continuation in
        schedule(generation, continuation: continuation, deadline: deadline)
      }
    } onCancel: {
      cancel(generation)
    }
  }
}

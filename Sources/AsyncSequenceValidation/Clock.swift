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

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram {
  public struct Clock: Sendable {
    let queue: WorkQueue

    init(queue: WorkQueue) {
      self.queue = queue
    }
  }
}

public protocol TestClock: Sendable {
  associatedtype Instant: TestInstant

  var now: Instant { get }

  func sleep(until deadline: Self.Instant, tolerance: Self.Instant.Duration?) async throws
}

public protocol TestInstant: Equatable {
  associatedtype Duration
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram.Clock {
  public struct Step: DurationProtocol, Hashable, CustomStringConvertible {
    internal var rawValue: Int

    internal init(_ rawValue: Int) {
      self.rawValue = rawValue
    }

    public static func + (lhs: Step, rhs: Step) -> Step {
      return .init(lhs.rawValue + rhs.rawValue)
    }

    public static func - (lhs: Step, rhs: Step) -> Step {
      .init(lhs.rawValue - rhs.rawValue)
    }

    public static func / (lhs: Step, rhs: Int) -> Step {
      .init(lhs.rawValue / rhs)
    }

    public static func * (lhs: Step, rhs: Int) -> Step {
      .init(lhs.rawValue * rhs)
    }

    public static func / (lhs: Step, rhs: Step) -> Double {
      Double(lhs.rawValue) / Double(rhs.rawValue)
    }

    public static func < (lhs: Step, rhs: Step) -> Bool {
      lhs.rawValue < rhs.rawValue
    }

    public static var zero: Step { .init(0) }

    public static func steps(_ amount: Int) -> Step {
      return Step(amount)
    }

    public var description: String {
      return "step \(rawValue)"
    }
  }

  public struct Instant: CustomStringConvertible {
    public typealias Duration = Step

    let when: Step

    public func advanced(by duration: Step) -> Instant {
      Instant(when: when + duration)
    }

    public func duration(to other: Instant) -> Step {
      other.when - when
    }

    public static func < (lhs: Instant, rhs: Instant) -> Bool {
      lhs.when < rhs.when
    }

    public var description: String {
      // the raw value is 1 indexed in execution but we should report it as 0 indexed
      return "tick \(when.rawValue - 1)"
    }
  }

  public var now: Instant {
    queue.now
  }

  public var minimumResolution: Step {
    .steps(1)
  }

  public func sleep(
    until deadline: Instant,
    tolerance: Step? = nil
  ) async throws {
    let token = queue.prepare()
    try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { continuation in
        queue.enqueue(
          AsyncSequenceValidationDiagram.Context.currentJob,
          deadline: deadline,
          continuation: continuation,
          token: token
        )
      }
    } onCancel: {
      queue.cancel(token)
    }
  }
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram.Clock.Instant: TestInstant {}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncSequenceValidationDiagram.Clock.Instant: InstantProtocol {}

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram.Clock: TestClock {}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AsyncSequenceValidationDiagram.Clock: Clock {}

// placeholders to avoid warnings
@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram.Clock.Instant: Hashable {}
@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram.Clock.Instant: Comparable {}

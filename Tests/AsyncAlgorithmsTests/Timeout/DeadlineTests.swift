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

#if compiler(>=6.2)
import Testing
import AsyncAlgorithms

@Suite
struct DeadlineTests {
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func timesoutCompleting() async throws {
    let result = try await withDeadline(
      until: .now.advanced(by: .milliseconds(1)),
      clock: .continuous
    ) {
      try? await typedSleep()
      return 1
    }
    #expect(result == 1)
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func timesoutThrowing() async throws {
    do {
      try await withDeadline(
        until: .now.advanced(by: .milliseconds(1)),
        clock: .continuous
      ) { () async throws(CancellationError) in
        try await typedSleep()
      }
      Issue.record("Expected DeadlineError.deadlineExceeded to be thrown")
    } catch {
      switch error.cause {
      case .deadlineExceeded:
        // Expected case
        break
      case .operationFailed:
        Issue.record("Expected deadlineExceeded but got operationFailed")
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func timesoutNonThrowing() async throws {
    try await withDeadline(
      until: .now.advanced(by: .milliseconds(1)),
      clock: .continuous
    ) { () async throws(Never) in
      try? await typedSleep()
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func completes() async throws {
    try await withDeadline(
      until: .now.advanced(by: .seconds(100)),
      clock: .continuous
    ) {
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func completesThrowing() async throws {
    do {
      try await withDeadline(
        until: .now.advanced(by: .seconds(100)),
        clock: .continuous
      ) { () throws(CancellationError) in
        throw CancellationError()
      }
      Issue.record("Expected DeadlineError.operationFailed to be thrown")
    } catch {
      switch error.cause {
      case .operationFailed:
        // Expected case - operation threw before timeout
        break
      case .deadlineExceeded:
        Issue.record("Expected operationFailed but got deadlineExceeded")
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func cancelledCompleting() async throws {
    let task = Task {
      try await withDeadline(
        until: .now.advanced(by: .seconds(100)),
        clock: .continuous
      ) {
        try? await Task.sleep(for: .seconds(100))
        // We are yielding a few times here just to ensure that we hit the
        // timeout child task to return first before the body
        for _ in 0..<100 {
          await Task.yield()
        }
        return 1
      }
    }
    task.cancel()
    let result = try await task.value
    #expect(result == 1)
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func cancelledThrowing() async throws {
    let task = Task {
      try await withDeadline(
        until: .now.advanced(by: .seconds(100)),
        clock: .continuous
      ) { () throws(CancellationError) in
        try? await Task.sleep(for: .seconds(100))
        // We are yielding a few times here just to ensure that we hit the
        // timeout child task to return first before the body
        for _ in 0..<100 {
          await Task.yield()
        }
        throw CancellationError()
      }
    }
    task.cancel()
    do {
      try await task.value
      Issue.record("Expected DeadlineError.deadlineExceeded to be thrown")
    } catch {
      switch (error as! DeadlineError<CancellationError, ContinuousClock>) .cause {
      case .deadlineExceeded:
        // Expected case - cancelled due to timeout
        break
      case .operationFailed:
        Issue.record("Expected deadlineExceeded but got operationFailed")
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func mainActorIsolatedClosure() async throws {
    try await withDeadline(
      until: .now.advanced(by: .seconds(100)),
      clock: .continuous
    ) { @MainActor in
      MainActor.assertIsolated()
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test
  func actorIsolatedClosure() async throws {
    try await withDeadline(
      until: .now.advanced(by: .seconds(100)),
      clock: .continuous
    ) {
      try await TestActor().timeout()
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  actor TestActor {
    func timeout() async throws {
      self.assertIsolated()
      try await withDeadline(
        until: .now.advanced(by: .seconds(100)),
        clock: .continuous
      ) {
        // We are hopping off here to another actor to see if we hop back
        await self.jump()
        self.assertIsolated()
      }
    }

    @MainActor
    func jump() async {
      await Task.yield()
    }
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  @Test(arguments: [ContinuousClock()])
  func dependencyInjection(clock: any Clock<Duration>) async throws {
    try await self.concreteClock(clock: clock)
  }

  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
  private func concreteClock(clock: some Clock<Duration>) async throws {
    try await withDeadline(
      until: clock.now.advanced(by: .seconds(10)),
      clock: clock
    ) {
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private func typedSleep() async throws(CancellationError) {
    do {
      try await Task.sleep(for: .seconds(100))
    } catch {
      throw error as! CancellationError
    }
  }
}
#endif

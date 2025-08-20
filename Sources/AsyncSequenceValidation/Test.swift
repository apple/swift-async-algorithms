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
import AsyncAlgorithms

@_silgen_name("swift_job_run")
@available(AsyncAlgorithms 1.0, *)
@usableFromInline
internal func _swiftJobRun(
  _ job: UnownedJob,
  _ executor: UnownedSerialExecutor
)

@available(AsyncAlgorithms 1.0, *)
public protocol AsyncSequenceValidationTest: Sendable {
  var inputs: [AsyncSequenceValidationDiagram.Specification] { get }
  var output: AsyncSequenceValidationDiagram.Specification { get }

  func test<C: TestClock>(
    with clock: C,
    activeTicks: [C.Instant],
    output: AsyncSequenceValidationDiagram.Specification,
    _ event: (String) -> Void
  ) async throws
}

@available(AsyncAlgorithms 1.0, *)
extension AsyncSequenceValidationDiagram {
  struct Test<Operation: AsyncSequence>: AsyncSequenceValidationTest, @unchecked Sendable
  where Operation.Element == String {
    let inputs: [Specification]
    let sequence: Operation
    let output: Specification

    func test<C: TestClock>(
      with clock: C,
      activeTicks: [C.Instant],
      output: Specification,
      _ event: (String) -> Void
    ) async throws {
      var iterator = sequence.makeAsyncIterator()
      do {
        for tick in activeTicks {
          if tick != clock.now {
            try await clock.sleep(until: tick, tolerance: nil)
          }
          guard let item = try await iterator.next() else {
            break
          }
          event(item)
        }
        do {
          if let pastEnd = try await iterator.next() {
            let failure = ExpectationFailure(
              when: Context.clock!.now,
              kind: .specificationViolationGotValueAfterIteration(pastEnd),
              specification: output
            )
            Context.specificationFailures.append(failure)
          }
        } catch {
          let failure = ExpectationFailure(
            when: Context.clock!.now,
            kind: .specificationViolationGotFailureAfterIteration(error),
            specification: output
          )
          Context.specificationFailures.append(failure)
        }
      } catch {
        throw error
      }
    }
  }

  struct Context {
    #if swift(<5.9)
    final class ClockExecutor: SerialExecutor {
      func enqueue(_ job: UnownedJob) {
        job._runSynchronously(on: self.asUnownedSerialExecutor())
      }

      func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
      }
    }

    private static let _executor = ClockExecutor()

    static var unownedExecutor: UnownedSerialExecutor {
      _executor.asUnownedSerialExecutor()
    }
    #else
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    final class ClockExecutor_5_9: SerialExecutor {
      func enqueue(_ job: __owned ExecutorJob) {
        job.runSynchronously(on: asUnownedSerialExecutor())
      }

      func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
      }
    }

    final class ClockExecutor_Pre5_9: SerialExecutor {
      @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
      @available(*, deprecated, message: "Implement 'enqueue(_: __owned ExecutorJob)' instead")
      func enqueue(_ job: UnownedJob) {
        job._runSynchronously(on: self.asUnownedSerialExecutor())
      }

      func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
      }
    }

    private static let _executor: AnyObject & Sendable = {
      guard #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) else {
        return ClockExecutor_Pre5_9()
      }
      return ClockExecutor_5_9()
    }()

    static var unownedExecutor: UnownedSerialExecutor {
      (_executor as! any SerialExecutor).asUnownedSerialExecutor()
    }
    #endif

    nonisolated(unsafe) static var clock: Clock?

    nonisolated(unsafe) static var driver: TaskDriver?

    nonisolated(unsafe) static var currentJob: Job?

    nonisolated(unsafe) static var specificationFailures = [ExpectationFailure]()
  }

  enum ActualResult {
    case success(String?)
    case failure(Error)
    case none

    init(_ result: Result<String?, Error>?) {
      if let result = result {
        switch result {
        case .success(let value):
          self = .success(value)
        case .failure(let error):
          self = .failure(error)
        }
      } else {
        self = .none
      }
    }
  }

  static func validate<Theme: AsyncSequenceValidationTheme>(
    inputs: [Specification],
    output: Specification,
    theme: Theme,
    expected: [ExpectationResult.Event],
    actual: [(Clock.Instant, Result<String?, Error>)]
  ) -> (ExpectationResult, [ExpectationFailure]) {
    let result = ExpectationResult(expected: expected, actual: actual)
    var failures = Context.specificationFailures
    Context.specificationFailures.removeAll()

    let actualTimes = actual.map { when, _ in when }
    let expectedTimes = expected.map { $0.when }

    var expectedMap = [Clock.Instant: [ExpectationResult.Event]]()
    var actualMap = [Clock.Instant: [Result<String?, Error>]]()

    for event in expected {
      expectedMap[event.when, default: []].append(event)
    }

    for (when, result) in actual {
      actualMap[when, default: []].append(result)
    }

    let allTimes = Set(actualTimes + expectedTimes).sorted()
    for when in allTimes {
      let expectedResults = expectedMap[when] ?? []
      let actualResults = actualMap[when] ?? []
      var expectedIterator = expectedResults.makeIterator()
      var actualIterator = actualResults.makeIterator()
      while let expectedEvent = expectedIterator.next() {
        let actualResult = ActualResult(actualIterator.next())
        switch (expectedEvent.result, actualResult) {
        case (.success(let expected), .success(let actual)):
          switch (expected, actual) {
          case (.some(let expected), .some(let actual)):
            if expected != actual {
              let failure = ExpectationFailure(
                when: when,
                kind: .expectedMismatch(expected, actual),
                specification: output,
                index: expectedEvent.offset
              )
              failures.append(failure)
            }
          case (.none, .some(let actual)):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinishButGotValue(actual),
              specification: output
            )
            failures.append(failure)
          case (.some(let expected), .none):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValueButGotFinished(expected),
              specification: output,
              index: expectedEvent.offset
            )
            failures.append(failure)
          case (.none, .none):
            break
          }
        case (.success(let expected), .failure(let actual)):
          if let expected = expected {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValueButGotFailure(expected, actual),
              specification: output,
              index: expectedEvent.offset
            )
            failures.append(failure)
          } else {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinishButGotFailure(actual),
              specification: output,
              index: expectedEvent.offset
            )
            failures.append(failure)
          }
        case (.success(let expected), .none):
          switch expected {
          case .some(let expected):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValue(expected),
              specification: output,
              index: expectedEvent.offset
            )
            failures.append(failure)
          case .none:
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinish,
              specification: output,
              index: expectedEvent.offset
            )
            failures.append(failure)
          }
        case (.failure(let expected), .success(let actual)):
          if let actual = actual {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFailureButGotValue(expected, actual),
              specification: output,
              index: expectedEvent.offset
            )
            failures.append(failure)
          } else {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFailureButGotFinish(expected),
              specification: output,
              index: expectedEvent.offset
            )
            failures.append(failure)
          }
        case (.failure, .failure):
          break
        case (.failure(let expected), .none):
          let failure = ExpectationFailure(
            when: when,
            kind: .expectedFailure(expected),
            specification: output,
            index: expectedEvent.offset
          )
          failures.append(failure)
        }
      }
      while let unexpectedResult = actualIterator.next() {
        switch unexpectedResult {
        case .success(let actual):
          switch actual {
          case .some(let actual):
            let failure = ExpectationFailure(
              when: when,
              kind: .unexpectedValue(actual),
              specification: output
            )
            failures.append(failure)
          case .none:
            let failure = ExpectationFailure(
              when: when,
              kind: .unexpectedFinish,
              specification: output
            )
            failures.append(failure)
          }
        case .failure(let actual):
          let failure = ExpectationFailure(
            when: when,
            kind: .unexpectedFailure(actual),
            specification: output
          )
          failures.append(failure)
        }
      }
    }

    return (result, failures)
  }

  public static func test<Test: AsyncSequenceValidationTest, Theme: AsyncSequenceValidationTheme>(
    theme: Theme,
    @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test
  ) throws -> (ExpectationResult, [ExpectationFailure]) {
    let diagram = AsyncSequenceValidationDiagram()
    let clock = diagram._clock
    let test = build(diagram)
    for index in 0..<test.inputs.count {
      // fault in all inputs
      _ = diagram.inputs[index]
    }

    for (index, input) in diagram.inputs.enumerated() {
      let inputSpecification = test.inputs[index]
      try input.parse(inputSpecification.specification, theme: theme, location: inputSpecification.location)
    }

    let parsedOutput = try Event.parse(test.output.specification, theme: theme, location: test.output.location)
    let cancelEvents = Set(
      parsedOutput.filter { when, event in
        switch event {
        case .cancel: return true
        default: return false
        }
      }.map { when, _ in return when }
    )

    let activeTicks = parsedOutput.reduce(into: [Clock.Instant.init(when: .zero)]) { events, thisEvent in
      switch thisEvent {
      case (let when, .delayNext(_)):
        events.removeLast()
        events.append(when.advanced(by: .steps(1)))
      case (let when, _):
        events.append(when)
      }
    }

    var expected = [ExpectationResult.Event]()
    for (when, event) in parsedOutput {
      for result in event.results {
        expected.append(ExpectationResult.Event(when: when, result: result, offset: event.index))
      }
    }
    let times = parsedOutput.map { when, _ in when }

    guard let end = (times + diagram.inputs.compactMap { $0.end }).max() else {
      return (ExpectationResult(expected: [], actual: []), [])
    }

    let actual = ManagedCriticalState([(Clock.Instant, Result<String?, Error>)]())
    Context.clock = clock
    Context.specificationFailures.removeAll()
    // This all needs to be isolated from potential Tasks (the caller function might be async!)
    Context.driver = TaskDriver(queue: diagram.queue) { driver in
      swift_task_enqueueGlobal_hook = { job, original in
        Context.driver?.enqueue(job)
      }

      let runner = Task {
        do {
          try await test.test(with: clock, activeTicks: activeTicks, output: test.output) { event in
            actual.withCriticalRegion { values in
              values.append((clock.now, .success(event)))
            }
          }
          actual.withCriticalRegion { values in
            values.append((clock.now, .success(nil)))
          }
        } catch {
          actual.withCriticalRegion { values in
            values.append((clock.now, .failure(error)))
          }
        }
      }

      // Drain off any initial work. Work may spawn additional work to be done.
      // If the driver ever becomes blocked on the clock, exit early out of that
      // drain, because the drain cant make any forward progress if it is blocked
      // by a needed clock advancement.
      diagram.queue.drain()
      // Next make sure to iterate a decent amount past the end of the maximum
      // scheduled things (that way we ensure any reasonable errors are caught)
      for _ in 0..<(end.when.rawValue * 2) {
        if cancelEvents.contains(diagram.queue.now.advanced(by: .steps(1))) {
          runner.cancel()
        }
        diagram.queue.advance()
      }

      runner.cancel()
      Context.clock = nil
      swift_task_enqueueGlobal_hook = nil
    }
    Context.driver?.start()
    // This is only valid since we are doing tests here
    // else wise this would cause QoS inversions
    Context.driver?.join()
    Context.driver = nil

    return validate(
      inputs: test.inputs,
      output: test.output,
      theme: theme,
      expected: expected,
      actual: actual.withCriticalRegion { $0 }
    )
  }

  public static func test<Test: AsyncSequenceValidationTest>(
    @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test
  ) throws -> (ExpectationResult, [ExpectationFailure]) {
    try self.test(theme: .ascii, build)
  }
}

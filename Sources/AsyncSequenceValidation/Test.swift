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

@_silgen_name("swift_job_run")
@usableFromInline
internal func _swiftJobRun(
  _ job: UnownedJob,
  _ executor: UnownedSerialExecutor
) -> ()

public protocol AsyncSequenceValidationTest: Sendable {
  var inputs: [String] { get }
  var output: String { get }
  
  func test(_ event: (String) -> Void) async throws
}

extension AsyncSequenceValidationDiagram {
  struct Test<Operation: AsyncSequence>: AsyncSequenceValidationTest, @unchecked Sendable where Operation.Element == String {
    let inputs: [String]
    let sequence: Operation
    let output: String
    
    func test(_ event: (String) -> Void) async throws {
      var iterator = sequence.makeAsyncIterator()
      do {
        while let item = try await iterator.next() {
          event(item)
        }
        do {
          if let pastEnd = try await iterator.next(){
            Context.specificationFailures.append(ExpectationFailure(when: Context.clock!.now, kind: .specificationViolationGotValueAfterIteration(pastEnd)))
          }
        } catch {
          Context.specificationFailures.append(ExpectationFailure(when: Context.clock!.now, kind: .specificationViolationGotFailureAfterIteration(error)))
        }
      } catch {
        throw error
      }
    }
  }
  
  struct Context {
    final class ClockExecutor: SerialExecutor {
      func enqueue(_ job: UnownedJob) {
        job._runSynchronously(on: asUnownedSerialExecutor())
      }
      
      func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
      }
    }
    
    static var clock: Clock?
    
    static let executor = ClockExecutor()
    
    static var driver: TaskDriver?
    
    static var currentJob: Job?
    
    static var specificationFailures = [ExpectationFailure]()
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
    output: String,
    theme: Theme,
    expected: [(Clock.Instant, Result<String?, Error>)],
    actual: [(Clock.Instant, Result<String?, Error>)]
  ) -> (ExpectationResult, [ExpectationFailure]) {
    let result = ExpectationResult(expected: expected, actual: actual)
    var failures = Context.specificationFailures
    Context.specificationFailures.removeAll()
    
    let actualTimes = actual.map { when, _ in when }
    let expectedTimes = expected.map { when, _ in when }
    
    var expectedMap = [Clock.Instant: [Result<String?, Error>]]()
    var actualMap = [Clock.Instant: [Result<String?, Error>]]()
    
    for (when, result) in expected {
      expectedMap[when, default: []].append(result)
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
      while let expectedResult = expectedIterator.next() {
        let actualResult = ActualResult(actualIterator.next())
        switch (expectedResult, actualResult) {
        case (.success(let expected), .success(let actual)):
          switch (expected, actual) {
          case (.some(let expected), .some(let actual)):
            if expected != actual {
              let failure = ExpectationFailure(
                when: when,
                kind: .expectedMismatch(expected, actual))
              failures.append(failure)
            }
          case (.none, .some(let actual)):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinishButGotValue(actual))
            failures.append(failure)
          case (.some(let expected), .none):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValueButGotFinished(expected))
            failures.append(failure)
          case (.none, .none):
            break
          }
        case (.success(let expected), .failure(let actual)):
          if let expected = expected {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValueButGotFailure(expected, actual))
            failures.append(failure)
          } else {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinishButGotFailure(actual))
            failures.append(failure)
          }
        case (.success(let expected), .none):
          switch expected {
          case .some(let expected):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValue(expected))
            failures.append(failure)
          case .none:
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinish)
            failures.append(failure)
          }
        case (.failure(let expected), .success(let actual)):
          if let actual = actual {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFailureButGotValue(expected, actual))
            failures.append(failure)
          } else {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFailureButGotFinish(expected))
            failures.append(failure)
          }
        case (.failure, .failure):
          break
        case (.failure(let expected), .none):
          let failure = ExpectationFailure(
            when: when,
            kind: .expectedFailure(expected))
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
              kind: .unexpectedValue(actual))
            failures.append(failure)
          case .none:
            let failure = ExpectationFailure(
              when: when,
              kind: .unexpectedFinish)
            failures.append(failure)
          }
        case .failure(let actual):
          let failure = ExpectationFailure(
            when: when,
            kind: .unexpectedFailure(actual))
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
    let clock = diagram.clock
    let test = build(diagram)
    for index in 0..<test.inputs.count {
      // fault in all inputs
      _ = diagram.inputs[index]
    }
    
    for (index, input) in diagram.inputs.enumerated() {
      try input.parse(test.inputs[index], theme: theme)
    }
    
    let parsedOutput = try Event.parse(test.output, theme: theme)
    let cancelEvents = Set(parsedOutput.filter { when, event in
      switch event {
      case .cancel: return true
      default: return false
      }
    }.map { when, _ in return when })
    
    var expected = [(Clock.Instant, Result<String?, Error>)]()
    for (when, event) in parsedOutput {
      for result in event.results {
        expected.append((when, result))
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
          try await test.test { event in
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
      output: test.output,
      theme: theme,
      expected: expected,
      actual: actual.withCriticalRegion { $0 })
  }
  
  public static func test<Test: AsyncSequenceValidationTest>(
    @AsyncSequenceValidationDiagram _ build: (AsyncSequenceValidationDiagram) -> Test
  ) throws -> (ExpectationResult, [ExpectationFailure]) {
    try self.test(theme: .ascii, build)
  }
}

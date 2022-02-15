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

@_silgen_name("swift_job_run")
@usableFromInline
internal func _swiftJobRun(
  _ job: UnownedJob,
  _ executor: UnownedSerialExecutor
) -> ()

public protocol MarbleDiagramTest: Sendable {
  var inputs: [String] { get }
  var output: String { get }
  
  func test(_ event: (String) -> Void) async throws
}

extension MarbleDiagram {
  struct Test<Operation: AsyncSequence>: MarbleDiagramTest, @unchecked Sendable where Operation.Element == String {
    let inputs: [String]
    let sequence: Operation
    let output: String
    
    func test(_ event: (String) -> Void) async throws {
      for try await item in sequence {
        event(item)
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
    
    static var clock: ManualClock?
    
    static let executor = ClockExecutor()
    
    static var driver: TaskDriver?
  }
  
  static func validate<Theme: MarbleDiagramTheme>(
    output: String,
    theme: Theme,
    expected: [ManualClock.Instant : Result<String?, Error>],
    actual: [(ManualClock.Instant, Result<String?, Error>)]
  ) -> [ExpectationFailure] {
#if false
    // useful to debug the marble diagram itself
    print("expected")
    for (when, result) in expected.map({ $0 }).sorted(by: { lhs, rhs in
      lhs.key < rhs.key
    }) {
      print(when.rawValue, result)
    }
    print("actual")
    for (when, result) in actual {
      print(when.rawValue, result)
    }
#endif
    var processed = Set<ManualClock.Instant>()
    var failures = [ExpectationFailure]()
    // reparse the output to fetch indicies
    let events = Event.parse(output, theme: theme).map { when, emission in
      return (when, emission.index)
    }
    let times = events.map { $0.0 }.sorted()
    let parsedOutput = Dictionary(uniqueKeysWithValues: events)
    func index(for when: ManualClock.Instant) -> String.Index {
      if let index = parsedOutput[when] {
        return index
      }
      // calculate a best guess for the index
      if let firstAfter = times.first(where: { $0 > when }) {
        if let followingEvent = parsedOutput[firstAfter] {
          if followingEvent > output.startIndex {
            return output.index(before: followingEvent)
          }
        }
      }
      return output.startIndex
    }
    for (when, actualResult) in actual {
      processed.insert(when)
      if let expectedResult = expected[when] {
        switch (expectedResult, actualResult) {
        case (.success(let expected), .success(let actual)):
          switch (expected, actual) {
          case (.some(let expected), .some(let actual)):
            if expected != actual {
              let failure = ExpectationFailure(
                when: when,
                kind: .expectedMismatch(expected, actual),
                index: index(for: when),
                output: output)
              failures.append(failure)
            }
          case (.none, .some(let actual)):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinishButGotValue(actual),
              index: index(for: when),
              output: output)
            failures.append(failure)
          case (.some(let expected), .none):
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValueButGotFinished(expected),
              index: index(for: when),
              output: output)
            failures.append(failure)
          case (.none, .none):
            break
          }
        case (.failure, .failure):
          break
        case (.failure(let expected), .success(let actual)):
          if let actual = actual {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFailureButGotValue(expected, actual),
              index: index(for: when),
              output: output)
            failures.append(failure)
          } else {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFailureButGotFinish(expected),
              index: index(for: when),
              output: output)
            failures.append(failure)
          }
        case (.success(let expected), .failure(let actual)):
          if let expected = expected {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedValueButGotFailure(expected, actual),
              index: index(for: when),
              output: output)
            failures.append(failure)
          } else {
            let failure = ExpectationFailure(
              when: when,
              kind: .expectedFinishButGotFailure(actual),
              index: index(for: when),
              output: output)
            failures.append(failure)
          }
        }
      } else {
        switch actualResult {
        case .success(let actual):
          switch actual {
          case .some(let actual):
            let failure = ExpectationFailure(
              when: when,
              kind: .unexpectedValue(actual),
              index: index(for: when),
              output: output)
            failures.append(failure)
          case .none:
            let failure = ExpectationFailure(
              when: when,
              kind: .unexpectedFinish,
              index: index(for: when),
              output: output)
            failures.append(failure)
          }
        case .failure(let actual):
          let failure = ExpectationFailure(
            when: when,
            kind: .unexpectedFailure(actual),
            index: index(for: when),
            output: output)
          failures.append(failure)
        }
      }
    }
    
    let unchecked = expected.keys.filter { !processed.contains($0) }
    for when in unchecked {
      guard let expectation = expected[when] else {
        continue
      }
      switch expectation {
      case .success(let expected):
        switch expected {
        case .some(let expected):
          let failure = ExpectationFailure(
            when: when,
            kind: .expectedValue(expected),
            index: index(for: when),
            output: output)
          failures.append(failure)
        case .none:
          let failure = ExpectationFailure(
            when: when,
            kind: .expectedFinish,
            index: index(for: when),
            output: output)
          failures.append(failure)
        }
      case .failure(let error):
        let failure = ExpectationFailure(
          when: when,
          kind: .expectedFailure(error),
          index: index(for: when),
          output: output)
        failures.append(failure)
      }
    }
    return failures
  }
  
  public static func test<Test: MarbleDiagramTest, Theme: MarbleDiagramTheme>(
    theme: Theme,
    @MarbleDiagram _ build: (inout MarbleDiagram) -> Test
  ) -> [ExpectationFailure] {
    let clock = ManualClock()
    
    var diagram = MarbleDiagram(clock)
    let test = build(&diagram)
    
    for (index, input) in diagram.inputs.enumerated() {
      input.parse(test.inputs[index], theme: theme)
    }
    
    let parsedOutput = Event.parse(test.output, theme: theme)
    let expected = Dictionary(uniqueKeysWithValues: parsedOutput.map { ($0, $1.result) })
    
    guard let end = (expected.keys + diagram.inputs.compactMap { $0.end }).max() else {
      return []
    }

    let actual = ManagedCriticalState([(ManualClock.Instant, Result<String?, Error>)]())
    Context.clock = clock
    // This all needs to be isolated from potential Tasks (the caller function might be async!)
    Context.driver = TaskDriver { driver in
      swift_task_enqueueGlobal_hook = { job, original in
        Context.driver?.enqueue(job) {
          _swiftJobRun(unsafeBitCast(job, to: UnownedJob.self), Context.executor.asUnownedSerialExecutor())
        }
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
      while driver.drain() {
        if clock.hasSleepers {
          break
        }
      }
      // Next make sure to iterate a decent amount past the end of the maximum
      // scheduled things (that way we ensure any reasonable errors are caught)
      for _ in 0..<(end.rawValue * 2) {
        clock.advance()
        // While the clock is not blocking any sleepers drain off any work.
        while !clock.hasSleepers {
          guard driver.drain() else {
            break
          }
        }
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
  
  public static func test<Test: MarbleDiagramTest>(
    @MarbleDiagram _ build: (inout MarbleDiagram) -> Test
  ) -> [ExpectationFailure] {
    self.test(theme: .ascii, build)
  }
}

import CMarableDiagram
import ClockStub

@_silgen_name("swift_job_run")
@usableFromInline
internal func _swiftJobRun(
  _ job: UnownedJob, 
  _ executor: UnownedSerialExecutor
) -> ()

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

public protocol MarbleDiagramTest: Sendable {
  var inputs: [String] { get }
  var output: String { get }
  
  func test(_ event: (String) -> Void) async throws
}

public protocol MarbleDiagramTheme {
  func token(_ character: Character, inValue: Bool) -> MarbleDiagram.Token
}

extension MarbleDiagramTheme where Self == MarbleDiagram.ASCIITheme {
  public static var ascii: MarbleDiagram.ASCIITheme {
    return MarbleDiagram.ASCIITheme()
  }
}

@resultBuilder
public struct MarbleDiagram : Sendable {
  public enum Token {
    case step
    case error
    case finish
    case beginValue
    case endValue
    case skip
    case value(String)
  }
  
  public struct ASCIITheme: MarbleDiagramTheme {
    public func token(_ character: Character, inValue: Bool) -> MarbleDiagram.Token {
      switch character {
      case "-": return .step
      case "^": return .error
      case "|": return .finish
      case "'": return inValue ? .endValue : .beginValue
      case " ": return .skip
      default: return .value(String(character))
      }
    }
  }
  
  struct Failure: Error, Equatable { }
  
  fileprivate struct Test<Operation: AsyncSequence>: MarbleDiagramTest, @unchecked Sendable where Operation.Element == String {
    let inputs: [String]
    let sequence: Operation
    let output: String
    
    func test(_ event: (String) -> Void) async throws {
      for try await item in sequence {
        event(item)
      }
    }
  }
  
  enum Event {
    case value(String, String.Index)
    case failure(Error, String.Index)
    case finish(String.Index)
    
    var result: Result<String?, Error> {
      switch self {
      case .value(let value, _): return .success(value)
      case .failure(let failure, _): return .failure(failure)
      case .finish: return .success(nil)
      }
    }
    
    var index: String.Index {
      switch self {
      case .value(_, let index): return index
      case .failure(_, let index): return index
      case .finish(let index): return index
      }
    }
    
    fileprivate static func parse<Theme: MarbleDiagramTheme>(_ dsl: String, theme: Theme) -> [(ManualClock.Instant, Event)] {
      var emissions = [(ManualClock.Instant, Event)]()
      var when = ManualClock.Instant(0)
      var string: String?
      
      for index in dsl.indices {
        let ch = dsl[index]
        switch theme.token(dsl[index], inValue: string != nil) {
        case .step:
          if string == nil {
            when += .steps(1)
          } else {
            string?.append(ch)
          }
        case .error:
          if string == nil {
            when += .steps(1)
            emissions.append((when, .failure(Failure(), index)))
          } else {
            string?.append(ch)
          }
        case .finish:
          if string == nil {
            when += .steps(1)
            emissions.append((when, .finish(index)))
          } else {
            string?.append(ch)
          }
        case .beginValue:
          string = ""
        case .endValue:
          if let value = string {
            string = nil
            when += .steps(1)
            emissions.append((when, .value(value, index)))
          }
        case .skip:
          string?.append(ch)
          continue
        case .value(let str):
          if string == nil {
            when += .steps(1)
            emissions.append((when, .value(String(ch), index)))
          } else {
            string?.append(str)
          }
        }
      }
      return emissions
    }
    
  }
  
  public struct Input: AsyncSequence, Sendable {
    public typealias Element = String
    
    fileprivate struct State {
      var emissions = [(ManualClock.Instant, Event)]()
    }
    
    fileprivate let state = ManagedCriticalState(State())
    fileprivate let clock: ManualClock
    
    public struct Iterator: AsyncIteratorProtocol {
      fileprivate let state: ManagedCriticalState<State>
      fileprivate let clock: ManualClock
      
      public mutating func next() async throws -> Element? {
        let next = state.withCriticalRegion { state -> (ManualClock.Instant, Event)? in
          guard state.emissions.count > 0 else {
            return nil
          }
          return state.emissions.removeFirst()
        }
        guard let next = next else {
          return nil
        }
        try? await clock.sleep(until: next.0)
        return try next.1.result.get()
      }
    }
    
    public func makeAsyncIterator() -> Iterator {
      Iterator(state: state, clock: clock)
    }
    
    func parse<Theme: MarbleDiagramTheme>(_ dsl: String, theme: Theme) {
      let emissions = Event.parse(dsl, theme: theme)
      state.withCriticalRegion { state in
        state.emissions = emissions
      }
    }
    
    var end: ManualClock.Instant? {
      return state.withCriticalRegion { state in
        state.emissions.map { $0.0 }.sorted().last
      }
    }
  }
  
  public struct Clock {
    fileprivate let manualClock: ManualClock
    
    fileprivate init(_ manualClock: ManualClock) {
      self.manualClock = manualClock
    }
  }
  
  public static func buildBlock<Operation: AsyncSequence>(
    _ input: String, 
    _ sequence: Operation, 
    _ output: String
  ) -> some MarbleDiagramTest where Operation.Element == String {
    return Test(inputs: [input], sequence: sequence, output: output)
  }
  
  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: String, 
    _ input2: String, 
    _ sequence: Operation, 
    _ output: String
  ) -> some MarbleDiagramTest where Operation.Element == String {
    Test(inputs: [input1, input2], sequence: sequence, output: output)
  }
  
  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: String, 
    _ input2: String, 
    _ input3: String, 
    _ sequence: Operation, 
    _ output: String
  ) -> some MarbleDiagramTest where Operation.Element == String {
    Test(inputs: [input1, input2, input3], sequence: sequence, output: output)
  }
  
  public struct InputList: RandomAccessCollection, Sendable {
    fileprivate let state = ManagedCriticalState([Input]())
    fileprivate let clock: ManualClock
    
    public var startIndex: Int { return 0 }
    public var endIndex: Int {
      state.withCriticalRegion { $0.count }
    }
    
    public subscript(position: Int) -> MarbleDiagram.Input {
      get {
        return state.withCriticalRegion { state in
          if position >= state.count {
            for _ in state.count...position {
              state.append(Input(clock: clock))
            }
          }
          return state[position]
        }
      }
    }
  }
  
  fileprivate let manualClock: ManualClock
  public var inputs: InputList
  
  public var clock: Clock {
    Clock(manualClock)
  }
  
  internal init(_ clock: ManualClock) {
    manualClock = clock
    inputs = InputList(clock: clock)
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
  
  public struct ExpectationFailure: CustomDebugStringConvertible {
    public enum Kind {
      case expectedFinishButGotValue(String)
      case expectedMismatch(String, String)
      case expectedValueButGotFinished(String)
      case expectedFailureButGotValue(Error, String)
      case expectedFailureButGotFinish(Error)
      case expectedValueButGotFailure(String, Error)
      case expectedFinishButGotFailure(Error)
      case expectedValue(String)
      case expectedFinish
      case expectedFailure(Error)
      case unexpectedValue(String)
      case unexpectedFinish
      case unexpectedFailure(Error)
    }
    public var when: ManualClock.Instant
    public var kind: Kind
    public var index: String.Index
    public var output: String
    
    var reason: String {
      switch kind {
      case .expectedFinishButGotValue(let actual):
        return "expected finish but got \"\(actual)\""
      case .expectedMismatch(let expected, let actual):
        return "expected \"\(expected)\" but got \"\(actual)\""
      case .expectedValueButGotFinished(let expected):
        return "expected \"\(expected)\" but got finish"
      case .expectedFailureButGotValue(_, let actual):
        return "expected failure but got \"\(actual)\""
      case .expectedFailureButGotFinish:
        return "expected failure but got finish"
      case .expectedValueButGotFailure(let expected, _):
        return "expected \"\(expected)\" but got failure"
      case .expectedFinishButGotFailure:
        return "expected finish but got failure"
      case .expectedValue(let expected):
        return "expected \"\(expected)\""
      case .expectedFinish:
        return "expected finish"
      case .expectedFailure:
        return "expected failure"
      case .unexpectedValue(let actual):
        return "unexpected \"\(actual)\""
      case .unexpectedFinish:
        return "unexpected finish"
      case .unexpectedFailure:
        return "unexpected failure"
      }
    }
    
    public var description: String {
      return reason + " at tick \(when.rawValue - 1)"
    }
    
    public var debugDescription: String {
      let delta = output.distance(from: output.startIndex, to: index)
      let padding = String(repeating: " ", count: delta)
      return output + "\n" + 
             padding + "^----- " + reason
    }
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

extension MarbleDiagram.Clock: Clock {
  public var now: ManualClock.Instant {
    manualClock.now
  }
  
  public var minimumResolution: ManualClock.Step {
    manualClock.minimumResolution
  }
  
  public func sleep(
    until deadline: ManualClock.Instant, 
    tolerance: ManualClock.Step? = nil
  ) async throws {
    try await manualClock.sleep(until: deadline, tolerance: tolerance)
  }
}

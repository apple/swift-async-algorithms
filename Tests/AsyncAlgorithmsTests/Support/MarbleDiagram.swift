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

import XCTest
import AsyncAlgorithms

public protocol MarbleDiagramTest: Sendable {
  var inputs: [String] { get }
  var output: String { get }
  
  func test(_ validator: Validator<String>, onFinish: @Sendable @escaping () -> Void)
}

extension XCTestCase {
  @resultBuilder
  public struct MarbleDiagram {
    struct Test<Operation: AsyncSequence>: MarbleDiagramTest, @unchecked Sendable where Operation.Element == String {
      let inputs: [String]
      let sequence: Operation
      let output: String
 
      func test(_ validator: Validator<String>, onFinish: @Sendable @escaping () -> Void) {
        validator.test(sequence) { _ in
          onFinish()
        }
      }
    }
    
    enum Event {
      case step
      case failure
      case finish
      case value(String)
    }
    
    public struct Input: AsyncSequence, Sendable {
      public typealias Element = String
      enum Emission {
        case value(Element)
        case failure(Error)
        case finish
        
        var result: Result<Element?, Error> {
          switch self {
          case .value(let value): return .success(value)
          case .failure(let failure): return .failure(failure)
          case .finish: return .success(nil)
          }
        }
      }
      
      struct State {
        var emissions = [(ManualClock.Instant, Emission)]()
        var continuations = [ManualClock.Instant: (Emission, UnsafeContinuation<Element?, Error>)]()
      }
      
      let state = ManagedCriticalState(State())
      let clock: ManualClock
      
      public struct Iterator: AsyncIteratorProtocol {
        let state: ManagedCriticalState<State>
        let clock: ManualClock
        
        public mutating func next() async throws -> Element? {
          let next = state.withCriticalRegion { state -> (ManualClock.Instant, Emission)? in
            guard state.emissions.count > 0 else {
              return nil
            }
            return state.emissions.removeFirst()
          }
          guard let next = next else {
            return nil
          }
          return try await withUnsafeThrowingContinuation { continuation in
            state.withCriticalRegion { state in
              state.continuations[next.0] = (next.1, continuation)
            }
          }
        }
      }
      
      public func makeAsyncIterator() -> Iterator {
        Iterator(state: state, clock: clock)
      }
      
      static func parse(_ dsl: String) -> [(ManualClock.Instant, Emission)] {
        var emissions = [(ManualClock.Instant, Emission)]()
        var when = ManualClock.Instant(0)
        for ch in dsl {
          switch ch {
          case "-":
            when += .steps(1)
          case "^":
            when += .steps(1)
            emissions.append((when, .failure(Failure())))
          case "|":
            when += .steps(1)
            emissions.append((when, .finish))
          case " ":
            continue
          default:
            when += .steps(1)
            emissions.append((when, .value(String(ch))))
          }
        }
        return emissions
      }
      
      func parse(_ dsl: String) {
        let emissions = Input.parse(dsl)
        state.withCriticalRegion { state in
          state.emissions = emissions
        }
      }
    }
    
    public struct Clock {
      let manualClock: ManualClock
      
      init(_ manualClock: ManualClock) {
        self.manualClock = manualClock
      }
    }
    
    public static func buildBlock<Operation: AsyncSequence>(_ input: String, _ sequence: Operation, _ output: String) -> some MarbleDiagramTest where Operation.Element == String {
      Test(inputs: [input], sequence: sequence, output: output)
    }
    
    public static func buildBlock<Operation: AsyncSequence>(_ input1: String, _ input2: String, _ sequence: Operation, _ output: String) -> some MarbleDiagramTest where Operation.Element == String {
      Test(inputs: [input1, input2], sequence: sequence, output: output)
    }
    
    let manualClock: ManualClock
    
    public var clock: Clock {
      Clock(manualClock)
    }
    
    public private(set) var inputs: [Input]
    
    init(clock: ManualClock, _ inputs: Input...) {
      self.inputs = inputs
      self.manualClock = clock
    }
  }
  
  public func marbleDiagram<Test: MarbleDiagramTest>(@MarbleDiagram _ build: (MarbleDiagram) -> Test, file: StaticString = #file, line: UInt = #line) {
    let finished = expectation(description: "finished")
    let clock = ManualClock()
    let input1 = MarbleDiagram.Input(clock: clock)
    let diagram = MarbleDiagram(clock: clock, input1)
    let test = build(diagram)
    input1.parse(test.inputs[0])
    var expected = Dictionary(uniqueKeysWithValues: MarbleDiagram.Input.parse(test.output).map { ($0, $1.result) })
    let actual = ManagedCriticalState([ManualClock.Instant:Result<String?, Error>]())
    let gate = Gate()
    let expectation = Gate()
    let validator = Validator<String> { event in
      actual.withCriticalRegion { actual in
        actual[clock.now] = event
      }
      await gate.enter()
      expectation.open()
    }
    test.test(validator) {
      finished.fulfill()
    }
    
    Task { [expected] in
      while true {
        clock.advance()
        
        let resumption = input1.state.withCriticalRegion { state in
          return state.continuations.removeValue(forKey: clock.now)
        }
        if let resumption = resumption {
          resumption.1.resume(with: resumption.0.result)
        }
        gate.open()
        if expected[clock.now] != nil {
          await expectation.enter()
        }
      }
    }
    wait(for: [finished], timeout: executionTimeAllowance)
    let collected = actual.withCriticalRegion { zip($0.keys, $0.values) }
    for (instant, result) in collected {
      if let expectedResult = expected.removeValue(forKey: instant) {
        switch (result, expectedResult) {
        case (.success(let actual), .success(let expected)):
          switch (actual, expected) {
          case (.some(let actual), .some(let expected)):
            if actual != expected {
              XCTFail("expected \(expected) at time index \(instant.rawValue) but got \(actual)", file: file, line: line)
            }
          case (.none, .some(let expected)):
            XCTFail("expected \(expected) at time index \(instant.rawValue) but got end of iteration", file: file, line: line)
          case (.some(let actual), .none):
            XCTFail("expected end of iteration at time index \(instant.rawValue) but got \(actual)", file: file, line: line)
          case (.none, .none):
            break
          }
        case (.failure(let error), .success(let expected)):
          if let expected = expected {
            XCTFail("expected \(expected) at time index \(instant.rawValue) but got failure \(error)", file: file, line: line)
          } else {
            XCTFail("expected end of iteration at time index \(instant.rawValue) but got failure \(error)", file: file, line: line)
          }
        case (.success(let actual), .failure):
          if let actual = actual {
            XCTFail("expected failure at time index \(instant.rawValue) but got \(actual)", file: file, line: line)
          } else {
            XCTFail("expected failure at time index \(instant.rawValue) but got end of iteration", file: file, line: line)
          }
        case (.failure, .failure):
          break
        }
      } else {
        switch result {
        case .success(let value):
          if let value = value {
            XCTFail("unexpected value \"\(value)\" at time index \(instant.rawValue)", file: file, line: line)
          } else {
            XCTFail("unexpected end of iteration at time index \(instant.rawValue)", file: file, line: line)
          }
        case .failure:
          XCTFail("unexpected failure at time index \(instant.rawValue)", file: file, line: line)
        }
      }
    }
    for (instant, result) in expected {
      switch result {
      case .success(let value):
        if let value = value {
          XCTFail("missing expected value \"\(value)\" at time index \(instant.rawValue)", file: file, line: line)
        } else {
          XCTFail("missing end of iteration at time index \(instant.rawValue)", file: file, line: line)
        }
      case .failure:
        XCTFail("missing failure at time index \(instant.rawValue)", file: file, line: line)
      }
    }
  }
}

extension XCTestCase.MarbleDiagram.Clock: Clock {
  public var now: ManualClock.Instant {
    manualClock.now
  }
  
  public var minimumResolution: ManualClock.Step {
    manualClock.minimumResolution
  }
  
  public func sleep(until deadline: ManualClock.Instant, tolerance: ManualClock.Step? = nil) async throws {
    try await manualClock.sleep(until: deadline, tolerance: tolerance)
  }
}

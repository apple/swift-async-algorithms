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

@resultBuilder
public struct AsyncSequenceValidationDiagram : Sendable {
  public struct AccumulatedInputs {
    var inputs: [Specification] = []
  }
  
  public struct AccumulatedInputsWithOperation<Operation: AsyncSequence> where Operation.Element == String {
    var inputs: [Specification]
    var operation: Operation
  }
  
  public static func buildBlock(_ input: String, file: StaticString = #file, line: UInt = #line) -> AccumulatedInputs {
    AccumulatedInputs(inputs: [Specification(specification: input, location: SourceLocation(file: file, line: line))])
  }
  
  public static func buildBlock<Operation: AsyncSequence>(_ operation: Operation, file: StaticString = #file, line: UInt = #line) -> AccumulatedInputsWithOperation<Operation> where Operation.Element == String {
    AccumulatedInputsWithOperation(inputs: [], operation: operation)
  }
  
  public static func buildBlock(combining input: String, into accumulated: AccumulatedInputs, file: StaticString = #file, line: UInt = #line) -> AccumulatedInputs {
    AccumulatedInputs(inputs: accumulated.inputs + [Specification(specification: input, location: SourceLocation(file: file, line: line))])
  }
  
  public static func buildBlock<Operation: AsyncSequence>(combining operation: Operation, into accumulated: AccumulatedInputs, file: StaticString = #file, line: UInt = #line) -> AccumulatedInputsWithOperation<Operation> {
    AccumulatedInputsWithOperation(inputs: accumulated.inputs, operation: operation)
  }
  
  public static func buildBlock<Operation: AsyncSequence>(combining output: String, into accumulated: AccumulatedInputsWithOperation<Operation>, file: StaticString = #file, line: UInt = #line) -> some AsyncSequenceValidationTest {
    Test(inputs: accumulated.inputs, sequence: accumulated.operation, output: Specification(specification: output, location: SourceLocation(file: file, line: line)))
  }

  let queue: WorkQueue
  
  public var inputs: InputList
  public let clock: Clock
  
  internal init() {
    let queue = WorkQueue()
    self.queue = queue
    self.inputs = InputList(queue: queue)
    self.clock = Clock(queue: queue)
  }
}


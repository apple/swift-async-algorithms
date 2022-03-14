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
  public struct Component<T> {
    var component: T
    var location: SourceLocation
  }
  
  public struct AccumulatedInputs {
    var inputs: [Specification] = []
  }
  
  public struct AccumulatedInputsWithOperation<Operation: AsyncSequence> where Operation.Element == String {
    var inputs: [Specification]
    var operation: Operation
  }
  
  public static func buildExpression(_ expr: String, file: StaticString = #file, line: UInt = #line) -> Component<String> {
    Component(component: expr, location: SourceLocation(file: file, line: line))
  }
  
  public static func buildExpression<S: AsyncSequence>(_ expr: S, file: StaticString = #file, line: UInt = #line) -> Component<S> {
    Component(component: expr, location: SourceLocation(file: file, line: line))
  }
  
  public static func buildPartialBlock(first input: Component<String>) -> AccumulatedInputs {
    return AccumulatedInputs(inputs: [Specification(specification: input.component, location: input.location)])
  }
  
  public static func buildPartialBlock<Operation: AsyncSequence>(first operation: Component<Operation>) -> AccumulatedInputsWithOperation<Operation> where Operation.Element == String {
    return AccumulatedInputsWithOperation(inputs: [], operation: operation.component)
  }
  
  public static func buildPartialBlock(accumulated: AccumulatedInputs, next input: Component<String>) -> AccumulatedInputs {
    return AccumulatedInputs(inputs: accumulated.inputs + [Specification(specification: input.component, location: input.location)])
  }
  
  public static func buildPartialBlock<Operation: AsyncSequence>(accumulated: AccumulatedInputs, next operation: Component<Operation>) -> AccumulatedInputsWithOperation<Operation> {
    return AccumulatedInputsWithOperation(inputs: accumulated.inputs, operation: operation.component)
  }
  
  public static func buildPartialBlock<Operation: AsyncSequence>(accumulated: AccumulatedInputsWithOperation<Operation>, next output: Component<String>) -> some AsyncSequenceValidationTest {
    return Test(inputs: accumulated.inputs, sequence: accumulated.operation, output: Specification(specification: output.component, location: output.location))
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


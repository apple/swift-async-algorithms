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
@available(AsyncAlgorithms 1.0, *)
public struct AsyncSequenceValidationDiagram: Sendable {
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

  public static func buildExpression(
    _ expr: String,
    file: StaticString = #file,
    line: UInt = #line
  ) -> Component<String> {
    Component(component: expr, location: SourceLocation(file: file, line: line))
  }

  public static func buildExpression<S: AsyncSequence>(
    _ expr: S,
    file: StaticString = #file,
    line: UInt = #line
  ) -> Component<S> {
    Component(component: expr, location: SourceLocation(file: file, line: line))
  }

  public static func buildPartialBlock(first input: Component<String>) -> AccumulatedInputs {
    return AccumulatedInputs(inputs: [Specification(specification: input.component, location: input.location)])
  }

  public static func buildPartialBlock<Operation: AsyncSequence>(
    first operation: Component<Operation>
  ) -> AccumulatedInputsWithOperation<Operation> where Operation.Element == String {
    return AccumulatedInputsWithOperation(inputs: [], operation: operation.component)
  }

  public static func buildPartialBlock(
    accumulated: AccumulatedInputs,
    next input: Component<String>
  ) -> AccumulatedInputs {
    return AccumulatedInputs(
      inputs: accumulated.inputs + [Specification(specification: input.component, location: input.location)]
    )
  }

  public static func buildPartialBlock<Operation: AsyncSequence>(
    accumulated: AccumulatedInputs,
    next operation: Component<Operation>
  ) -> AccumulatedInputsWithOperation<Operation> {
    return AccumulatedInputsWithOperation(inputs: accumulated.inputs, operation: operation.component)
  }

  public static func buildPartialBlock<Operation: AsyncSequence>(
    accumulated: AccumulatedInputsWithOperation<Operation>,
    next output: Component<String>
  ) -> some AsyncSequenceValidationTest {
    return Test(
      inputs: accumulated.inputs,
      sequence: accumulated.operation,
      output: Specification(specification: output.component, location: output.location)
    )
  }

  public static func buildBlock<Operation: AsyncSequence>(
    _ sequence: Component<Operation>,
    _ output: Component<String>
  ) -> some AsyncSequenceValidationTest where Operation.Element == String {
    let part1 = buildPartialBlock(first: sequence)
    let part2 = buildPartialBlock(accumulated: part1, next: output)
    return part2
  }

  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: Component<String>,
    _ sequence: Component<Operation>,
    _ output: Component<String>
  ) -> some AsyncSequenceValidationTest where Operation.Element == String {
    let part1 = buildPartialBlock(first: input1)
    let part2 = buildPartialBlock(accumulated: part1, next: sequence)
    let part3 = buildPartialBlock(accumulated: part2, next: output)
    return part3
  }

  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: Component<String>,
    _ input2: Component<String>,
    _ sequence: Component<Operation>,
    _ output: Component<String>
  ) -> some AsyncSequenceValidationTest where Operation.Element == String {
    let part1 = buildPartialBlock(first: input1)
    let part2 = buildPartialBlock(accumulated: part1, next: input2)
    let part3 = buildPartialBlock(accumulated: part2, next: sequence)
    let part4 = buildPartialBlock(accumulated: part3, next: output)
    return part4
  }

  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: Component<String>,
    _ input2: Component<String>,
    _ input3: Component<String>,
    _ sequence: Component<Operation>,
    _ output: Component<String>
  ) -> some AsyncSequenceValidationTest where Operation.Element == String {
    let part1 = buildPartialBlock(first: input1)
    let part2 = buildPartialBlock(accumulated: part1, next: input2)
    let part3 = buildPartialBlock(accumulated: part2, next: input3)
    let part4 = buildPartialBlock(accumulated: part3, next: sequence)
    let part5 = buildPartialBlock(accumulated: part4, next: output)
    return part5
  }

  public static func buildBlock<Operation: AsyncSequence>(
    _ input1: Component<String>,
    _ input2: Component<String>,
    _ input3: Component<String>,
    _ input4: Component<String>,
    _ sequence: Component<Operation>,
    _ output: Component<String>
  ) -> some AsyncSequenceValidationTest where Operation.Element == String {
    let part1 = buildPartialBlock(first: input1)
    let part2 = buildPartialBlock(accumulated: part1, next: input2)
    let part3 = buildPartialBlock(accumulated: part2, next: input3)
    let part4 = buildPartialBlock(accumulated: part3, next: input3)
    let part5 = buildPartialBlock(accumulated: part4, next: sequence)
    let part6 = buildPartialBlock(accumulated: part5, next: output)
    return part6
  }

  let queue: WorkQueue
  let _clock: Clock

  public var inputs: InputList

  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public var clock: Clock {
    _clock
  }

  internal init() {
    let queue = WorkQueue()
    self.queue = queue
    self.inputs = InputList(queue: queue)
    self._clock = Clock(queue: queue)
  }
}

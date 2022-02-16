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

@resultBuilder
public struct MarbleDiagram : Sendable {
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
  
  let queue: WorkQueue
  
  public var inputs: InputList
  public let clock: Clock
  
  internal init() {
    let queue = WorkQueue()
    let clock = Clock(queue: queue)
    self.queue = queue
    self.inputs = InputList(clock: clock)
    self.clock = clock
  }
}


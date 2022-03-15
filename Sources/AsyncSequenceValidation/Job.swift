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

@available(macOS 9999, iOS 9999, tvOS 9999, watchOS 9999, *)
struct Job: Hashable, @unchecked Sendable {
  let job: JobRef
  
  init(_ job: JobRef) {
    self.job = job
  }
  
  func execute() {
    _swiftJobRun(unsafeBitCast(job, to: UnownedJob.self), AsyncSequenceValidationDiagram.Context.executor.asUnownedSerialExecutor())
  }
}

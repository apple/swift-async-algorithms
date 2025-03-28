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

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
struct Job: Hashable, @unchecked Sendable {
  let job: JobRef

  init(_ job: JobRef) {
    self.job = job
  }

  func execute() {
    _swiftJobRun(unsafeBitCast(job, to: UnownedJob.self), AsyncSequenceValidationDiagram.Context.unownedExecutor)
  }
}

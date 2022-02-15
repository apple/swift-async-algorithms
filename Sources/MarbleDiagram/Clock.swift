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

import ClockStub

extension MarbleDiagram {
  public struct Clock {
    let manualClock: ManualClock
    
    init(_ manualClock: ManualClock) {
      self.manualClock = manualClock
    }
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

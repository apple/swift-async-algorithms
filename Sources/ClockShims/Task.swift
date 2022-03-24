//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Task where Success == Never, Failure == Never {
  public static func sleep<C: Clock>(
    until deadine: C.Instant,
    tolerance: C.Instant.Duration? = nil,
    clock: C
  ) async throws {
    try await clock.sleep(until: deadine, tolerance: tolerance)
  }
}

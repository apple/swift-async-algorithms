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

// This is a hack around the fact that we don't have generic effects
// alternatively in the use cases we would want `rethrows(unsafe)`
// or something like that to avoid this nifty hack...

@rethrows
internal protocol _ErrorMechanism {
  associatedtype Output
  func get() throws -> Output
}

extension _ErrorMechanism {
  // rethrow an error only in the cases where it is known to be reachable
  internal func _rethrowError() rethrows -> Never {
    _ = try _rethrowGet()
    fatalError("materialized error without being in a throwing context")
  }

  internal func _rethrowGet() rethrows -> Output {
    return try get()
  }
}

extension Result: _ErrorMechanism {}

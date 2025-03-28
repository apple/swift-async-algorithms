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

struct Failure: Error, Equatable {}

func throwOn<T: Equatable>(_ toThrowOn: T, _ value: T) throws -> T {
  if value == toThrowOn {
    throw Failure()
  }
  return value
}

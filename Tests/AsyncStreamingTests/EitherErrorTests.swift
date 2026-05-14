//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming && compiler(>=6.4)
import AsyncStreaming
import Testing

@Suite
struct EitherErrorTests {
  enum FirstError: Error, Equatable, Hashable {
    case one
    case two
  }

  enum SecondError: Error, Equatable, Hashable {
    case alpha
    case beta
  }

  @Test
  func unwrapFirst() throws {
    let error: EitherError<FirstError, SecondError> = .first(.one)

    #expect(throws: FirstError.one) {
      try error.unwrap()
    }
  }

  @Test
  func unwrapSecond() throws {
    let error: EitherError<FirstError, SecondError> = .second(.alpha)

    #expect(throws: SecondError.alpha) {
      try error.unwrap()
    }
  }

  @Test
  func equatable() {
    let a: EitherError<FirstError, SecondError> = .first(.one)
    let b: EitherError<FirstError, SecondError> = .first(.one)
    let c: EitherError<FirstError, SecondError> = .first(.two)
    let d: EitherError<FirstError, SecondError> = .second(.alpha)

    #expect(a == b)
    #expect(a != c)
    #expect(a != d)
  }

  @Test
  func hashable() {
    let a: EitherError<FirstError, SecondError> = .first(.one)
    let b: EitherError<FirstError, SecondError> = .first(.one)
    let c: EitherError<FirstError, SecondError> = .second(.alpha)

    #expect(a.hashValue == b.hashValue)
    #expect(a.hashValue != c.hashValue)
  }
}
#endif

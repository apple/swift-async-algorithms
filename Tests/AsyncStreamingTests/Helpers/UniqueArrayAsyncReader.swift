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
import BasicContainers
import ContainersPreview

struct UniqueArrayAsyncReader: ~Copyable, AsyncReader {
  typealias ReadElement = Int
  typealias Buffer = UniqueArray<Int>
  typealias ReadFailure = Never
  typealias FinalElement = Void

  var storage: UniqueArray<Int>
  var didEmitFinal: Bool = false

  mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout UniqueArray<Int>, Void?) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    precondition(!self.didEmitFinal, "read called after end-of-stream")
    self.didEmitFinal = true
    do {
      var uniqueArray = self.storage.clone()
      self.storage = .init()
      return try await body(&uniqueArray, .some(()))
    } catch {
      throw .second(error)
    }
  }
}
#endif

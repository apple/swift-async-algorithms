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

  var storage: UniqueArray<Int>

  mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout UniqueArray<Int>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    do {
      var uniqueArray = self.storage.clone()
      self.storage = .init()
      return try await body(&uniqueArray)
    } catch {
      throw .second(error)
    }
  }
}
#endif

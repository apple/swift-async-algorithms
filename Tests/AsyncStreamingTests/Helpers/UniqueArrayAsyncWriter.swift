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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct UniqueArrayAsyncWriter: ~Copyable, AsyncWriter {
  typealias WriteElement = Int
  typealias Buffer = UniqueArray<Int>
  typealias WriteFailure = Never

  var storage: UniqueArray<Int>

  init(capacity: Int = 100) {
    self.storage = UniqueArray(minimumCapacity: capacity)
  }

  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout UniqueArray<Int>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    var buffer = UniqueArray<Int>(minimumCapacity: 64)
    do {
      let result = try await body(&buffer)
      self.storage.append(copying: buffer)
      return result
    } catch {
      throw .second(error)
    }
  }
}
#endif

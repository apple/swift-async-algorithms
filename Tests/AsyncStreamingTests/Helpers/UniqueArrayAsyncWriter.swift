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
import SpanPreview

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
struct UniqueArrayAsyncWriter: ~Copyable, AsyncWriter {
  typealias WriteElement = Int
  typealias WriteFailure = Never
  typealias FinalElement = Void

  var storage: UniqueArray<Int>
  var didFinish: Bool = false

  init(capacity: Int = 100) {
    self.storage = UniqueArray(minimumCapacity: capacity)
  }

  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout OutputSpan<Int>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    let capacity = 64
    let scratch = UnsafeMutableBufferPointer<Int>.allocate(capacity: capacity)
    defer { scratch.deallocate() }
    var output = OutputSpan(buffer: scratch, initializedCount: 0)
    do {
      let result = try await body(&output)
      let count = output.finalize(for: scratch)
      self.storage.append(copying: Span(_unsafeStart: scratch.baseAddress!, count: count))
      return result
    } catch {
      throw .second(error)
    }
  }

  consuming func finish(
    finalElement: consuming Void
  ) async throws(Never) {
    self.didFinish = true
  }
}
#endif

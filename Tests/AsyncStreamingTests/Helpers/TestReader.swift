//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming
import _AsyncStreaming
import BasicContainers

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct SimpleReader: AsyncReader {
  typealias ReadElement = Int
  typealias ReadFailure = Never

  var data: [Int]
  var position: Int = 0

  mutating func read<Return, Failure: Error>(
    maximumCount: Int?,
    body: (consuming Span<Int>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    do {
      guard position < data.count else {
        return try await body([Int]().span)
      }

      let count: Int
      if let maximumCount {
        count = min(maximumCount, data.count - position)
      } else {
        count = data.count - position
      }

      let endIndex = position + count
      defer { position = endIndex }
      return try await body(data[position..<endIndex].span)
    } catch {
      throw .second(error)
    }
  }
}
#endif

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
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Array {
  /// Creates an async reader that provides access to the array's elements.
  ///
  /// This method converts an array into an ``AsyncReader`` implementation, allowing
  /// the array's elements to be read through the async reader interface.
  ///
  /// - Returns: An ``AsyncReader`` that produces all elements of the array.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let numbers = [1, 2, 3, 4, 5]
  /// var reader = numbers.asyncReader()
  ///
  /// try await reader.forEach { span in
  ///     print("Read \(span.count) numbers")
  /// }
  /// ```
  public func asyncReader() -> some AsyncReader<Element, Never> & SendableMetatype {
    return ArrayAsyncReader(array: self)
  }
}

/// An async reader implementation that provides array elements through the AsyncReader interface.
///
/// This internal reader type wraps an array and delivers its elements through the ``AsyncReader``
/// protocol. It maintains a current read position and can deliver elements in chunks based on
/// the requested maximum count.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ArrayAsyncReader<Element>: AsyncReader {
  typealias ReadElement = Element
  typealias ReadFailure = Never

  let array: [Element]
  var index: Array<Element>.Index

  init(array: [Element]) {
    self.array = array
    self.index = array.startIndex
  }

  mutating func read<Return, Failure: Error>(
    maximumCount: Int?,
    body: (consuming Span<Element>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    do {
      guard self.index < self.array.endIndex else {
        return try await body([Element]().span)
      }

      guard let maximumCount else {
        defer {
          self.index = self.array.span.indices.endIndex
        }
        return try await body(self.array.span.extracting(self.index...))
      }
      let endIndex = min(
        self.array.span.indices.endIndex,
        self.index.advanced(
          by: maximumCount
        )
      )
      defer {
        self.index = endIndex
      }
      return try await body(self.array.span.extracting(self.index..<endIndex))
    } catch {
      throw .second(error)
    }
  }
}
#endif

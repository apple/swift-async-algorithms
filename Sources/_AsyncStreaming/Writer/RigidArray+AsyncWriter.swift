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
public import BasicContainers

/// Conforms `RigidArray` to the ``AsyncWriter`` protocol.
///
/// This extension enables `RigidArray` to be used as an asynchronous writer, allowing
/// elements to be appended through the async writer interface.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension RigidArray: AsyncWriter {
  /// Provides a buffer to write elements into the rigid array.
  ///
  /// This method allocates space for elements in the array and provides an `OutputSpan`
  /// that the body closure can use to append elements. The method appends up to the
  /// specified count of elements to the array.
  ///
  /// - Parameter body: A closure that receives an `OutputSpan` to write elements into.
  ///
  /// - Returns: The value returned by the body closure.
  ///
  /// - Throws: Any error thrown by the body closure.
  ///
  /// ## Example
  ///
  /// ```swift
  /// var array = RigidArray<Int>()
  ///
  /// try await array.write { outputSpan in
  ///     for i in 0..<5 {
  ///         outputSpan.append(i)
  ///     }
  /// }
  /// ```
  public mutating func write<Result, Failure: Error>(
    _ body: (inout OutputSpan<Element>) async throws(Failure) -> Result
  ) async throws(EitherError<Never, Failure>) -> Result {
    do {
      // TODO: Reconsider adding count to AsyncWriter
      return try await self.append(count: 10) { (outputSpan) async throws(Failure) -> Result in
        try await body(&outputSpan)
      }
    } catch {
      throw .second(error)
    }
  }
}
#endif

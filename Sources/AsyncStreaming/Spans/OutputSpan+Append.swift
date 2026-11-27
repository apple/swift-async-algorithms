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

public import SpanPreview

public import ContainersPreview

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension OutputSpan where Element: Copyable {
  /// Appends copies of all elements of `source` in a single memory copy.
  ///
  /// - Parameter source: The elements to append. Their count must not exceed
  ///   ``freeCapacity``.
  @inlinable
  public mutating func append(copying source: Span<Element>) {
    let count = source.count
    precondition(count <= self.freeCapacity, "The output span has not enough free capacity")
    guard count > 0 else { return }
    unsafe self.withUnsafeMutableBufferPointer { destination, initializedCount in
      unsafe source.withUnsafeBufferPointer { source in
        unsafe (destination.baseAddress! + initializedCount).initialize(
          from: source.baseAddress!,
          count: count
        )
      }
      initializedCount &+= count
    }
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension OutputSpan where Element: ~Copyable {
  /// Moves as many elements from the front of `source` as fit into the free
  /// capacity.
  ///
  /// - Parameter source: The elements to move. Keeps the elements that did not fit.
  /// - Returns: The number of elements that moved.
  @inlinable
  @discardableResult
  @_lifetime(self: copy self)
  @_lifetime(source: copy source)
  public mutating func append(moving source: inout InputSpan<Element>) -> Int {
    let count = Swift.min(source.count, self.freeCapacity)
    guard count > 0 else { return 0 }
    unsafe source.withUnsafeMutableBufferPointer { sourceBuffer, sourceCount in
      let start = sourceBuffer.count &- sourceCount
      unsafe self.withUnsafeMutableBufferPointer { destination, initializedCount in
        unsafe (destination.baseAddress! + initializedCount).moveInitialize(
          from: sourceBuffer.baseAddress! + start,
          count: count
        )
        initializedCount &+= count
      }
      sourceCount &-= count
    }
    return count
  }
}
#endif

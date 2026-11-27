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

// The standard library lends `OutputSpan` only to synchronous closures. These
// methods keep the spans alive across suspension points. The array lives in a
// heap allocation while a span is lent, since an async function cannot form a
// stable pointer to a local value.

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension InlineArray where Element: ~Copyable {
  /// Creates an array whose elements an asynchronous closure appends to an
  /// output span.
  ///
  /// - Parameter initializer: Appends the elements. It must append exactly
  ///   `count` elements; otherwise the initializer traps.
  @inlinable
  @_disfavoredOverload
  public init<Failure: Error>(
    initializingWith initializer: (inout OutputSpan<Element>) async throws(Failure) -> Void
  ) async throws(Failure) {
    let storage = UnsafeMutablePointer<Self>.allocate(capacity: 1)
    defer { unsafe storage.deallocate() }
    let elements = unsafe UnsafeMutableBufferPointer(
      start: UnsafeMutableRawPointer(storage).assumingMemoryBound(to: Element.self),
      count: count
    )
    var output = unsafe OutputSpan(buffer: elements, initializedCount: 0)
    do throws(Failure) {
      try await initializer(&output)
    } catch {
      let initializedCount = unsafe output.finalize(for: elements)
      unsafe elements.baseAddress?.deinitialize(count: initializedCount)
      throw error
    }
    let initializedCount = unsafe output.finalize(for: elements)
    precondition(initializedCount == count, "The initializer did not initialize all elements")
    self = unsafe storage.move()
  }

  /// Consumes the array and lends its elements to an asynchronous closure as
  /// an input span.
  ///
  /// - Parameter consumer: Takes the elements out of the input span. The
  ///   elements that it leaves are destroyed.
  /// - Returns: The value that `consumer` returns.
  @inlinable
  @_disfavoredOverload
  public consuming func consumeAll<Return: ~Copyable, Failure: Error>(
    consumingWith consumer: (inout InputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    // The input span destroys the elements, so the array itself must not.
    let storage = UnsafeMutablePointer<Self>.allocate(capacity: 1)
    unsafe storage.initialize(to: self)
    defer { unsafe storage.deallocate() }
    let elements = unsafe UnsafeMutableBufferPointer(
      start: UnsafeMutableRawPointer(storage).assumingMemoryBound(to: Element.self),
      count: count
    )
    var input = unsafe InputSpan(buffer: elements, initializedCount: count)
    return try await consumer(&input)
  }
}
#endif

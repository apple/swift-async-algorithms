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
// overloads keep the span alive across suspension points, so that an array can
// be the target of an asynchronous read. They can go away once the standard
// library has an asynchronous form of these methods. They are disfavored, so
// that a synchronous closure keeps calling the synchronous method.

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension Array {
  /// Appends up to `uninitializedCount` elements by lending the free capacity
  /// to an asynchronous closure as an output span.
  ///
  /// The array keeps the elements that `initializer` appended, also when it throws.
  ///
  /// ```swift
  /// var bytes = [UInt8]()
  /// let final = try await bytes.append(addingCapacity: 4096) { output in
  ///     try await reader.read(into: &output)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - uninitializedCount: The number of elements that the output span can hold.
  ///   - initializer: Appends the new elements to the output span.
  /// - Returns: The value that `initializer` returns.
  @inlinable
  @_disfavoredOverload
  public mutating func append<Return: ~Copyable, Failure: Error>(
    addingCapacity uninitializedCount: Int,
    initializingWith initializer: (inout OutputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    precondition(uninitializedCount >= 0, "uninitializedCount must not be negative")
    // Reserves the free capacity and escapes a pointer to it. The array is not
    // mutated until the commit below, so the pointer stays valid.
    var freeCapacity = unsafe UnsafeMutableBufferPointer<Element>(start: nil, count: 0)
    self.append(addingCapacity: uninitializedCount) { output in
      unsafe output.withUnsafeMutableBufferPointer { buffer, _ in
        unsafe freeCapacity = buffer
      }
    }
    var output = unsafe OutputSpan(buffer: freeCapacity, initializedCount: 0)
    let result: Result<Return, Failure>
    do throws(Failure) {
      result = .success(try await initializer(&output))
    } catch {
      result = .failure(error)
    }
    let initializedCount = unsafe output.finalize(for: freeCapacity)
    self.append(addingCapacity: initializedCount) { output in
      unsafe output.withUnsafeMutableBufferPointer { buffer, count in
        precondition(
          unsafe buffer.baseAddress == freeCapacity.baseAddress,
          "The array moved its storage while the output span was alive"
        )
        count = initializedCount
      }
    }
    return try result.get()
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension Array where Element: BitwiseCopyable {
  /// Removes all elements and lends them to an asynchronous closure as an
  /// input span.
  ///
  /// The array keeps its capacity, so it can be refilled without an allocation.
  ///
  /// ```swift
  /// try await bytes.consumeAll { elements in
  ///     try await writer.write(&elements)
  /// }
  /// ```
  ///
  /// - Parameter consumer: Takes the elements out of the input span. The
  ///   elements that it leaves are removed too.
  /// - Returns: The value that `consumer` returns.
  @inlinable
  @_disfavoredOverload
  public mutating func consumeAll<Return: ~Copyable, Failure: Error>(
    consumingWith consumer: (inout InputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    // Escapes a pointer to the elements. The array is not mutated until the
    // removal below, and the elements need no deinitialization.
    let elements = unsafe self.withUnsafeMutableBufferPointer { unsafe $0 }
    defer { self.removeAll(keepingCapacity: true) }
    var input = unsafe InputSpan(buffer: elements, initializedCount: elements.count)
    return try await consumer(&input)
  }
}
#endif

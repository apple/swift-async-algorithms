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

public import BasicContainers
public import ContainersPreview

// BasicContainers lends `OutputSpan` and `InputSpan` only to synchronous
// closures. These overloads keep the spans alive across suspension points.
// They are disfavored, so that a synchronous closure keeps calling the
// synchronous method.

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension UniqueArray where Element: ~Copyable {
  /// Appends up to `newItemCount` elements by lending the free capacity to an
  /// asynchronous closure as an output span.
  ///
  /// The array keeps the elements that `initializer` appended, also when it throws.
  ///
  /// - Parameters:
  ///   - newItemCount: The number of elements that the output span can hold.
  ///   - initializer: Appends the new elements to the output span.
  /// - Returns: The value that `initializer` returns.
  @inlinable
  @_disfavoredOverload
  public mutating func append<Return: ~Copyable, Failure: Error>(
    addingCount newItemCount: Int,
    initializingWith initializer: (inout OutputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    precondition(newItemCount >= 0, "newItemCount must not be negative")
    // Reserves the free capacity and escapes a pointer to it. The array is not
    // mutated until the commit below, so the pointer stays valid.
    var freeCapacity = unsafe UnsafeMutableBufferPointer<Element>(start: nil, count: 0)
    self.append(addingCount: newItemCount) { output in
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
    self.append(addingCount: initializedCount) { output in
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

  /// Removes all elements and lends them to an asynchronous closure as an
  /// input span.
  ///
  /// - Parameter consumer: Takes the elements out of the input span. The
  ///   elements that it leaves are destroyed.
  /// - Returns: The value that `consumer` returns.
  @inlinable
  @_disfavoredOverload
  public mutating func consumeAll<Return: ~Copyable, Failure: Error>(
    consumingWith consumer: (inout InputSpan<Element>) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    // The subrange consumer removes the elements from the array when it is
    // destroyed. The storage is contiguous, so a single span holds them all.
    // An empty array may have no storage, so it lends an empty span instead.
    guard !self.isEmpty else {
      var input = InputSpan<Element>()
      return try await consumer(&input)
    }
    let count = self.count
    var subrange = self.consumeSubrange(0..<count)
    var input = subrange.drainNext(maxCount: count)
    return try await consumer(&input)
  }
}
#endif

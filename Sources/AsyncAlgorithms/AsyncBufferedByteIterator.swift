//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// An `AsyncIterator` that provides a convenient and high-performance implementation
/// of a common architecture for `AsyncSequence` of `UInt8`, otherwise known as byte streams.
///
/// Bytes are read into an internal buffer of `capacity` bytes via the
/// `readFunction`. Invoking `next()` returns bytes from the internal buffer until it's
/// empty, and then suspends and awaits another invocation of `readFunction` to
/// refill. If `readFunction` returns 0 (indicating nothing was read), `next()` will
/// return `nil` from then on. Cancellation is checked before each invocation of
/// `readFunction`, which means that many calls to `next()` will not check for
/// cancellation.
///
/// A typical use of `AsyncBufferedByteIterator` looks something like this:
///
///     struct AsyncBytes: AsyncSequence {
///       public typealias Element = UInt8
///       var handle: ReadableThing
///
///       internal init(_ readable: ReadableThing) {
///         handle = readable
///       }
///
///       public func makeAsyncIterator() -> AsyncBufferedByteIterator {
///         return AsyncBufferedByteIterator(capacity: 16384) { buffer in
///           // This runs once every 16384 invocations of next()
///           return try await handle.read(into: buffer)
///         }
///       }
///     }
///
///
@available(AsyncAlgorithms 1.0, *)
public struct AsyncBufferedByteIterator: AsyncIteratorProtocol {
  public typealias Element = UInt8
  @usableFromInline var buffer: _AsyncBytesBuffer

  /// Creates an asynchronous buffered byte iterator with a specified capacity and read function.
  ///
  /// - Parameters:
  ///   - capacity: The maximum number of bytes that a single invocation of `readFunction` may produce.
  ///   This is the allocated capacity of the backing buffer for iteration; the value must be greater than 0.
  ///   - readFunction: The function for refilling the buffer.
  public init(
    capacity: Int,
    readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int
  ) {
    buffer = _AsyncBytesBuffer(capacity: capacity, readFunction: readFunction)
  }

  /// Reads a byte out of the buffer if available. When no bytes are available, this will trigger
  /// the read function to reload the buffer and then return the next byte from that buffer.
  @inlinable @inline(__always)
  public mutating func next() async throws -> UInt8? {
    return try await buffer.next()
  }
}

@available(*, unavailable)
extension AsyncBufferedByteIterator: Sendable {}

@available(AsyncAlgorithms 1.0, *)
@frozen @usableFromInline
internal struct _AsyncBytesBuffer {
  @usableFromInline
  final class Storage {
    fileprivate let buffer: UnsafeMutableRawBufferPointer

    init(
      capacity: Int
    ) {
      precondition(capacity > 0)
      buffer = UnsafeMutableRawBufferPointer.allocate(
        byteCount: capacity,
        alignment: MemoryLayout<AnyObject>.alignment
      )
    }

    deinit {
      buffer.deallocate()
    }
  }

  @usableFromInline internal let storage: Storage
  @usableFromInline internal var nextPointer: UnsafeRawPointer
  @usableFromInline internal var endPointer: UnsafeRawPointer

  internal let readFunction: @Sendable (UnsafeMutableRawBufferPointer) async throws -> Int
  internal var finished = false

  @usableFromInline init(
    capacity: Int,
    readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int
  ) {
    let s = Storage(capacity: capacity)
    self.readFunction = readFunction
    storage = s
    nextPointer = UnsafeRawPointer(s.buffer.baseAddress!)
    endPointer = nextPointer
  }

  @inline(never) @usableFromInline
  internal mutating func reloadBufferAndNext() async throws -> UInt8? {
    if finished {
      return nil
    }
    try Task.checkCancellation()
    do {
      let readSize: Int = try await readFunction(storage.buffer)
      if readSize == 0 {
        finished = true
        nextPointer = endPointer
        return nil
      }
      nextPointer = UnsafeRawPointer(storage.buffer.baseAddress!)
      endPointer = nextPointer + readSize
    } catch {
      finished = true
      nextPointer = endPointer
      throw error
    }
    return try await next()
  }

  @inlinable @inline(__always)
  internal mutating func next() async throws -> UInt8? {
    if _fastPath(nextPointer != endPointer) {
      let byte = nextPointer.load(fromByteOffset: 0, as: UInt8.self)
      nextPointer = nextPointer + 1
      return byte
    }
    return try await reloadBufferAndNext()
  }
}

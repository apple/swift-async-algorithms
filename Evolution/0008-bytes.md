# AsyncBufferedByteIterator

* Proposal: [SAA-0008](https://github.com/apple/swift-async-algorithms/blob/main/Evolution/0008-bytes.md)
* Authors: [David Smith](https://github.com/Catfish-Man), [Philippe Hausler](https://github.com/phausler)
* Status: **Accepted**
* Implementation: [[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncBufferedByteIterator.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestBufferedByteIterator.swift)]

## Introduction

Sources of bytes are a common point of asynchrony; reading from files, reading from the network, or other such tasks. Having an easy to use, uniform, and performant utility to make this approachable is key to unlocking highly scalable byte handling. This has proven useful for `FileHandle`, `URL`, and a number of others in Foundation.  

This type provides infrastructure for creating `AsyncSequence` types with an `Element` of `UInt8` backed by file descriptors or similar read sources.

```swift
struct AsyncBytes: AsyncSequence {
  public typealias Element = UInt8
  var handle: ReadableThing

  internal init(_ readable: ReadableThing) {
    handle = readable
  }

  public func makeAsyncIterator() -> AsyncBufferedByteIterator {
    return AsyncBufferedByteIterator(capacity: 16384) { buffer in
      // This runs once every 16384 invocations of next()
      return try await handle.read(into: buffer)
    }
  }
}
```

## Detailed Design

```swift
public struct AsyncBufferedByteIterator: AsyncIteratorProtocol {
  public typealias Element = UInt8

  public init(
    capacity: Int,
    readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int
  )

  public mutating func next() async throws -> UInt8?
}
```

For each invocation of `next`, the iterator will check if a buffer has been filled. If the buffer is filled with some amount of bytes, a fast path is taken to directly return a byte out of that buffer. If the buffer is not filled, the read function is invoked to acquire the next filled buffer, at which point it takes a byte out of that buffer.

If the read function returns `0`, indicating it didn't read any more bytes, the iterator is decided to be finished and no additional invocations to the read function are made.

If the read function throws, the error will be thrown by the iteration. Subsequent invocations to the iterator will then return `nil` without invoking the read function.

If the task is cancelled during the iteration, the iteration will check the cancellation only in passes where the read function is invoked, and will throw a `CancellationError`.

### Naming

This type was named precisely for what it does: it is an asynchronous iterator that buffers bytes. 


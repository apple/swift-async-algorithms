# AsyncBufferedByteIterator

[[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncBufferedByteIterator.swift) | 
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestBufferedByteIterator.swift)]

Provides a highly effecient iterator useful for iterating byte sequences derived from asynchronous read functions.

This type can provide the infrastructure to allow for taking file descriptors or other such read sources and making them into `AsyncSequence` types with an element of `UInt8`

```swift
public struct AsyncBytes: AsyncSequence {
  actor Handle {
    var fd: Int32

    init(_ fd: Int32) {
      self.fd = fd
    }

    deinit {
      close(fd)
    }

    func readBytes(
      into buffer: UnsafeMutableRawBufferPointer
    ) async throws -> Int {
      let amount =
        read(fd, buffer.baseAddress, buffer.count)
      guard amount >= 0 else {
        throw Failure(errno)
      }
      return amount
    }
  }
  public typealias Element = UInt8
  public typealias AsyncIterator = AsyncBufferedByteIterator
  var handle: Handle

  internal init(_ fd: Int32) {
    handle = Handle(fd)
  }

  public func makeAsyncIterator() -> AsyncBufferedByteIterator {
    return AsyncBufferedByteIterator(capacity: 16384) { buffer in
      // This runs once every 16384 invocations of next()
      return try await handle.readBytes(into: buffer)
    }
  }
}
```

## Detailed Design

```swift
public struct AsyncBufferedByteIterator: AsyncIteratorProtocol, Sendable {
  public typealias Element = UInt8

  public init(
    capacity: Int,
    readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int
  )

  public mutating func next() async throws -> UInt8?
}
```

For each invocation of `next` the iterator will check if a buffer has been filled. If the buffer is filled with some amount of bytes a fast path is taken to directly return a byte out of that buffer. If the buffer is not filled then the read function is invoked to acquire the next filled buffer and then it takes a byte out of that buffer.

If at any point in time the buffer is filled with returning a count of 0 the iterator is claimed to be finished, and no additional invocations to the read function is made.

If at any point of reloading the read function throws, the error will be thrown by the iteration. Subsequent invocations to the iterator will return nil without invoking the read function.

During the iteration if the task is cancelled the iteration will check the cancellation only in passes where the read function is invoked and will throw a `CancellationError`.

### Naming

This type was named precicely for what it does: it is an asynchronous iterator that buffers bytes. 


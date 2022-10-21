//
//  AsyncBufferedChannel.swift
//  
//
//  Created by Thibault Wittemberg on 06/11/2022.
//

/// A channel for sending elements from one task to another.
/// The back pressure is handled by buffering values until a limit is reached
/// and then by suspending send operations until there are available slots in the buffer.
///
/// The `AsyncBufferedChannel` class is intended to be used as a communication type between tasks,
/// particularly when one task produces values and another task consumes those values.
///
/// Although the `send(_:)` function is marked `async`, it will suspend only if the internal buffer is full.
/// It will be resumed when a call to `next()` frees a slot in the buffer.
///
/// The `finish()` function marks the channel as terminated. The buffered and suspended elements
/// will remain available and dequeued on calls to `next()`.
/// In this terminal state, a call to `send(_:)` will resume immediately and the element will be discarded.
public final class AsyncBufferedChannel<Element>: AsyncSequence {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  let storage: BufferedChannelStorage<Element>
  #if DEBUG
  var onSendSuspended: (() -> Void)? {
    didSet {
      self.storage.onSendSuspended = onSendSuspended
    }
  }
  var onNextSuspended: (() -> Void)? {
    didSet {
      self.storage.onNextSuspended = onNextSuspended
    }
  }
  #endif

  public init(bufferSize: UInt) {
    precondition(bufferSize > 0, "This channel requires a buffer size greater than 0 to be efficient, otherwise use `AsyncChannel`.")
    self.storage = BufferedChannelStorage(bufferSize: bufferSize)
  }

  /// Sends an element to the channel. The call will suspended only
  /// if there are no awaiting iteration or if the internal buffer is full.
  /// If the function suspends and the task is cancelled, the function will resume and the element will be discarded.
  /// If the function buffers the element or suspends and the `finish()` function is called
  /// from another task, the remaining elements are still available for consumption
  /// and the function will resume only when the element is consumed.
  public func send(_ element: Element) async {
    await self.storage.send(element: element)
  }

  /// Marks the channel as terminated.
  /// All the buffered elements and suspended `send(_:)` calls are still available for consumption.
  /// The future calls to `send(_:)` will resume immediately.
  public func finish() {
    self.storage.finish()
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(storage: self.storage)
  }

  public struct Iterator: AsyncIteratorProtocol {
    let storage: BufferedChannelStorage<Element>
    
    public mutating func next() async -> Element? {
      await self.storage.next()
    }
  }
}

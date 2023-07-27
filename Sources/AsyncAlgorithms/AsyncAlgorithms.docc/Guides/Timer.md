# Timer

* Author(s): [Philippe Hausler](https://github.com/phausler)

[
[Source](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncTimerSequence.swift) |
[Tests](https://github.com/apple/swift-async-algorithms/blob/main/Tests/AsyncAlgorithmsTests/TestTimer.swift)
]

## Introduction

Producing elements at regular intervals can be useful for composing with other algorithms. These can range from invoking code at specific times to using those regular intervals as a delimiter of events. There are other cases this exists in APIs however those do not currently interact with Swift concurrency. These existing APIs are ones like `Timer` or `DispatchTimer` but are bound to internal clocks that are not extensible.

## Proposed Solution

We propose to add a new type; `AsyncTimerSequence` which utilizes the new `Clock`, `Instant` and `Duration` types. This allows the interaction of the timer to custom implementations of types adopting `Clock`.

This asynchronous sequence will produce elements of the clock's `Instant` type after the interval has elapsed. That instant will be the `now` at the time that the sleep has resumed. For each invocation to `next()` the `AsyncTimerSequence.Iterator` will calculate the next deadline to resume and pass that and the tolerance to the clock. If at any point in time the task executing that iteration is cancelled the iteration will return `nil` from the call to `next()`.

```swift
public struct AsyncTimerSequence<C: Clock>: AsyncSequence {
  public typealias Element = C.Instant
  
  public struct Iterator: AsyncIteratorProtocol {
    public mutating func next() async -> C.Instant?
  }
  
  public init(
    interval: C.Instant.Duration, 
    tolerance: C.Instant.Duration? = nil, 
    clock: C
  )
  
  public func makeAsyncIterator() -> Iterator
}

extension AsyncTimerSequence where C == SuspendingClock {
  public static func repeating(every interval: Duration, tolerance: Duration? = nil) -> AsyncTimerSequence<SuspendingClock>
}

extension AsyncTimerSequence: Sendable { }
extension AsyncTimerSequence.Iterator: Sendable { }
```

Since all the types comprising `AsyncTimerSequence` are `Sendable` these types are also `Sendable`.

## Credits/Inspiration

https://developer.apple.com/documentation/foundation/timer

https://developer.apple.com/documentation/foundation/timer/timerpublisher

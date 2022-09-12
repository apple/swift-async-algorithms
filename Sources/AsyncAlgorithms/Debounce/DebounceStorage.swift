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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class DebounceStorage<Base: AsyncSequence, C: Clock>: @unchecked Sendable where Base: Sendable {
    typealias Element = Base.Element

    /// The lock that protects our state.
    private let lock = Lock.allocate()
    /// The state machine.
    private var stateMachine: DebounceStateMachine<Base, C>
    /// The interval to debounce.
    private let interval: C.Instant.Duration
    /// The tolerance for the clock.
    private let tolerance: C.Instant.Duration?
    /// The clock.
    private let clock: C

    init(base: Base, interval: C.Instant.Duration, tolerance: C.Instant.Duration?, clock: C) {
        self.stateMachine = .init(base: base, clock: clock, interval: interval)
        self.interval = interval
        self.tolerance = tolerance
        self.clock = clock
    }

    deinit {
        self.lock.deinitialize()
    }

    func sequenceDeinitialized() {
        self.lock.withLock { self.stateMachine.sequenceDeinitialized() }
    }

    func iteratorInitialized() {
        self.lock.withLockVoid {
            let action = self.stateMachine.iteratorInitialized()

            switch action {
            case .startTask(let base):
                let task = Task {
                    await withThrowingTaskGroup(of: Void.self) { group in
                        // The task that consumes the upstream sequence
                        group.addTask {
                            var iterator = base.makeAsyncIterator()

                            // This is our upstream consumption loop
                            loop: while true {
                                // We are creating a continuation before requesting the next
                                // element from upstream. This continuation is only resumed
                                // if the downstream consumer called `next` to signal his demand
                                // and until the Clock sleep finished.
                                try await withUnsafeThrowingContinuation { continuation in
                                    let action = self.lock.withLock {
                                        self.stateMachine.upstreamTaskSuspended(continuation)
                                    }

                                    switch action {
                                    case .resumeContinuation(let continuation):
                                        // This happens if there is outstanding demand
                                        // and we need to demand from upstream right away
                                        continuation.resume(returning: ())

                                    case .resumeContinuationWithError(let continuation, let error):
                                        // This happens if the task got cancelled.
                                        continuation.resume(throwing: error)

                                    case .none:
                                        break
                                    }
                                }

                                // We got signalled from the downstream that we have demand so let's
                                // request a new element from the upstream
                                if let element = try await iterator.next() {
                                    let action = self.lock.withLock {
                                        let deadline = self.clock.now.advanced(by: self.interval)
                                        return self.stateMachine.elementProduced(element, deadline: deadline)
                                    }

                                    switch action {
                                    case .resumeClockContinuation(let clockContinuation, let deadline):
                                        clockContinuation?.resume(returning: deadline)

                                    case .none:
                                        break
                                    }
                                } else {
                                    // The upstream returned `nil` which indicates that it finished
                                    let action = self.lock.withLock {
                                        self.stateMachine.upstreamFinished()
                                    }

                                    // All of this is mostly cleanup around the Task and the outstanding
                                    // continuations used for signalling.
                                    switch action {
                                    case .cancelTaskAndClockContinuation(let task, let clockContinuation):
                                        task.cancel()
                                        clockContinuation?.resume(throwing: CancellationError())

                                        break loop
                                    case .resumeContinuationWithNilAndCancelTaskAndUpstreamAndClockContinuation(
                                        let downstreamContinuation,
                                        let task,
                                        let upstreamContinuation,
                                        let clockContinuation
                                    ):
                                        upstreamContinuation?.resume(throwing: CancellationError())
                                        clockContinuation?.resume(throwing: CancellationError())
                                        task.cancel()

                                        downstreamContinuation.resume(returning: nil)

                                        break loop

                                    case .resumeContinuationWithElementAndCancelTaskAndUpstreamAndClockContinuation(
                                        let downstreamContinuation,
                                        let element,
                                        let task,
                                        let upstreamContinuation,
                                        let clockContinuation
                                    ):
                                        upstreamContinuation?.resume(throwing: CancellationError())
                                        clockContinuation?.resume(throwing: CancellationError())
                                        task.cancel()

                                        downstreamContinuation.resume(returning: element)

                                        break loop


                                    case .none:

                                        break loop
                                    }
                                }
                            }
                        }

                        group.addTask {
                            // This is our clock scheduling loop
                            loop: while true {
                                do {
                                    // We are creating a continuation sleeping on the Clock.
                                    // This continuation is only resumed if the downstream consumer called `next`.
                                    let deadline: C.Instant = try await withUnsafeThrowingContinuation { continuation in
                                        let action = self.lock.withLock {
                                            self.stateMachine.clockTaskSuspended(continuation)
                                        }

                                        switch action {
                                        case .resumeContinuation(let continuation, let deadline):
                                            // This happens if there is outstanding demand
                                            // and we need to demand from upstream right away
                                            continuation.resume(returning: deadline)

                                        case .resumeContinuationWithError(let continuation, let error):
                                            // This happens if the task got cancelled.
                                            continuation.resume(throwing: error)

                                        case .none:
                                            break
                                        }
                                    }

                                    try await self.clock.sleep(until: deadline, tolerance: self.tolerance)

                                    let action = self.lock.withLock {
                                        self.stateMachine.clockSleepFinished()
                                    }

                                    switch action {
                                    case .resumeDownStreamContinuation(let downStreamContinuation, let element):
                                        downStreamContinuation.resume(returning: element)

                                    case .none:
                                        break
                                    }
                                } catch {
                                    // The only error that we expect is the `CancellationError`
                                    // thrown from the Clock.sleep or from the withUnsafeContinuation.
                                    // This happens if we are cleaning everything up. We can just drop that error and break our loop
                                    precondition(error is CancellationError, "Received unexpected error \(error) in the Clock loop")
                                    break loop
                                }
                            }
                        }

                        do {
                            try await group.waitForAll()
                        } catch {
                            // The upstream sequence threw an error
                            let action = self.lock.withLock {
                                self.stateMachine.upstreamThrew(error)
                            }

                            switch action {
                            case .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuation(
                                let downstreamContinuation,
                                let error,
                                let task,
                                let upstreamContinuation,
                                let clockContinuation
                            ):
                                upstreamContinuation?.resume(throwing: CancellationError())
                                clockContinuation?.resume(throwing: CancellationError())

                                task.cancel()

                                downstreamContinuation.resume(throwing: error)

                            case .cancelTaskAndClockContinuation(
                                let task,
                                let clockContinuation
                            ):
                                clockContinuation?.resume(throwing: CancellationError())
                                task.cancel()

                            case .none:
                                break
                            }

                            group.cancelAll()
                        }
                    }
                }

                self.stateMachine.taskStarted(task)
            }
        }
    }

    func iteratorDeinitialized() {
        let action = self.lock.withLock { self.stateMachine.iteratorDeinitialized() }

        switch action {
        case .cancelTaskAndUpstreamAndClockContinuations(
            let task,
            let upstreamContinuation,
            let clockContinuation
        ):
            upstreamContinuation?.resume(throwing: CancellationError())
            clockContinuation?.resume(throwing: CancellationError())

            task.cancel()

        case .none:
            break
        }
    }

    func next() async rethrows -> Element? {
        // We need to handle cancellation here because we are creating a continuation
        // and because we need to cancel the `Task` we created to consume the upstream
        return try await withTaskCancellationHandler {
            // We always suspend since we can never return an element right away

            self.lock.lock()
            return try await withUnsafeThrowingContinuation { continuation in
                let action = self.stateMachine.next(for: continuation)
                self.lock.unlock()

                switch action {
                case .resumeUpstreamContinuation(let upstreamContinuation):
                    // This is signalling the upstream task that is consuming the upstream
                    // sequence to signal demand.
                    upstreamContinuation?.resume(returning: ())

                case .resumeUpstreamAndClockContinuation(let upstreamContinuation, let clockContinuation, let deadline):
                    // This is signalling the upstream task that is consuming the upstream
                    // sequence to signal demand and start the clock task.
                    upstreamContinuation?.resume(returning: ())
                    clockContinuation?.resume(returning: deadline)

                case .resumeDownstreamContinuationWithNil(let continuation):
                    continuation.resume(returning: nil)

                case .resumeDownstreamContinuationWithError(let continuation, let error):
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            let action = self.lock.withLock { self.stateMachine.cancelled() }

            switch action {
            case .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamAndClockContinuation(
                let downstreamContinuation,
                let task,
                let upstreamContinuation,
                let clockContinuation
            ):
                upstreamContinuation?.resume(throwing: CancellationError())
                clockContinuation?.resume(throwing: CancellationError())

                task.cancel()

                downstreamContinuation.resume(returning: nil)

            case .none:
                break
            }
        }
    }
}

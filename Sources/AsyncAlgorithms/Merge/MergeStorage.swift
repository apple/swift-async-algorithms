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

final class MergeStorage<
    Base1: AsyncSequence,
    Base2: AsyncSequence,
    Base3: AsyncSequence
>: @unchecked Sendable where
    Base1.Element == Base2.Element,
    Base1.Element == Base3.Element,
    Base1: Sendable, Base2: Sendable, Base3: Sendable,
    Base1.Element: Sendable
{
    typealias Element = Base1.Element

    /// The lock that protects our state.
    private let lock = Lock.allocate()
    /// The state machine.
    private var stateMachine: MergeStateMachine<Base1, Base2, Base3>

    init(
        base1: Base1,
        base2: Base2,
        base3: Base3?
    ) {
        stateMachine = .init(base1: base1, base2: base2, base3: base3)
    }

    deinit {
        self.lock.deinitialize()
    }

    func sequenceDeinitialized() {
        lock.withLock { self.stateMachine.sequenceDeinitialized() }
    }

    func iteratorInitialized() {
        lock.withLockVoid {
            let action = self.stateMachine.iteratorInitialized()

            // We are holding the lock while creating the `Task`
            // because we need to make sure that only one iterator is ever created
            // we could avoid holding the lock here by just introducing another state
            // in the state machine but that seems like an overkill
            switch action {
            case let .startTask(base1, base2, base3):
                // This creates a new `Task` that is iterating the upstream
                // sequences. We must store it to cancel it at the right times.
                let task = Task {
                    await withThrowingTaskGroup(of: Void.self) { group in
                        // For each upstream sequence we are adding a child task that
                        // is consuming the upstream sequence
                        group.addTask {
                            var iterator1 = base1.makeAsyncIterator()

                            // This is our upstream consumption loop
                            loop: while true {
                                // We are creating a continuation before requesting the next
                                // element from upstream. This continuation is only resumed
                                // if the downstream consumer called `next` to signal his demand.
                                try await withUnsafeThrowingContinuation { continuation in
                                    let action = self.lock.withLock {
                                        self.stateMachine.childTaskSuspended(continuation)
                                    }

                                    switch action {
                                    case let .resumeContinuation(continuation):
                                        // This happens if there is outstanding demand
                                        // and we need to demand from upstream right away
                                        continuation.resume(returning: ())

                                    case let .resumeContinuationWithError(continuation, error):
                                        // This happens if another upstream already failed or if
                                        // the task got cancelled.
                                        continuation.resume(throwing: error)

                                    case .none:
                                        break
                                    }
                                }

                                // We got signalled from the downstream that we have demand so let's
                                // request a new element from the upstream
                                if let element1 = try await iterator1.next() {
                                    let action = self.lock.withLock {
                                        self.stateMachine.elementProduced(element1)
                                    }

                                    switch action {
                                    case let .resumeContinuation(continuation, element):
                                        // We had an outstanding demand and where the first
                                        // upstream to produce an element so we can forward it to
                                        // the downstream
                                        continuation.resume(returning: element)

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
                                    case let .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                                        downstreamContinuation,
                                        task,
                                        upstreamContinuations
                                    ):
                                        upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                                        task.cancel()

                                        downstreamContinuation.resume(returning: nil)

                                        break loop

                                    case let .cancelTaskAndUpstreamContinuations(
                                        task,
                                        upstreamContinuations
                                    ):
                                        upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                                        task.cancel()

                                        break loop
                                    case .none:

                                        break loop
                                    }
                                }
                            }
                        }

                        // Copy from the above just using the base2 sequence
                        group.addTask {
                            var iterator2 = base2.makeAsyncIterator()

                            // This is our upstream consumption loop
                            loop: while true {
                                // We are creating a continuation before requesting the next
                                // element from upstream. This continuation is only resumed
                                // if the downstream consumer called `next` to signal his demand.
                                try await withUnsafeThrowingContinuation { continuation in
                                    let action = self.lock.withLock {
                                        self.stateMachine.childTaskSuspended(continuation)
                                    }

                                    switch action {
                                    case let .resumeContinuation(continuation):
                                        // This happens if there is outstanding demand
                                        // and we need to demand from upstream right away
                                        continuation.resume(returning: ())

                                    case let .resumeContinuationWithError(continuation, error):
                                        // This happens if another upstream already failed or if
                                        // the task got cancelled.
                                        continuation.resume(throwing: error)

                                    case .none:
                                        break
                                    }
                                }

                                // We got signalled from the downstream that we have demand so let's
                                // request a new element from the upstream
                                if let element2 = try await iterator2.next() {
                                    let action = self.lock.withLock {
                                        self.stateMachine.elementProduced(element2)
                                    }

                                    switch action {
                                    case let .resumeContinuation(continuation, element):
                                        // We had an outstanding demand and where the first
                                        // upstream to produce an element so we can forward it to
                                        // the downstream
                                        continuation.resume(returning: element)

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
                                    case let .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                                        downstreamContinuation,
                                        task,
                                        upstreamContinuations
                                    ):
                                        upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                                        task.cancel()

                                        downstreamContinuation.resume(returning: nil)

                                        break loop

                                    case let .cancelTaskAndUpstreamContinuations(
                                        task,
                                        upstreamContinuations
                                    ):
                                        upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                                        task.cancel()

                                        break loop
                                    case .none:

                                        break loop
                                    }
                                }
                            }
                        }

                        // Copy from the above just using the base3 sequence
                        if let base3 = base3 {
                            group.addTask {
                                var iterator3 = base3.makeAsyncIterator()

                                // This is our upstream consumption loop
                                loop: while true {
                                    // We are creating a continuation before requesting the next
                                    // element from upstream. This continuation is only resumed
                                    // if the downstream consumer called `next` to signal his demand.
                                    try await withUnsafeThrowingContinuation { continuation in
                                        let action = self.lock.withLock {
                                            self.stateMachine.childTaskSuspended(continuation)
                                        }

                                        switch action {
                                        case let .resumeContinuation(continuation):
                                            // This happens if there is outstanding demand
                                            // and we need to demand from upstream right away
                                            continuation.resume(returning: ())

                                        case let .resumeContinuationWithError(continuation, error):
                                            // This happens if another upstream already failed or if
                                            // the task got cancelled.
                                            continuation.resume(throwing: error)

                                        case .none:
                                            break
                                        }
                                    }

                                    // We got signalled from the downstream that we have demand so let's
                                    // request a new element from the upstream
                                    if let element3 = try await iterator3.next() {
                                        let action = self.lock.withLock {
                                            self.stateMachine.elementProduced(element3)
                                        }

                                        switch action {
                                        case let .resumeContinuation(continuation, element):
                                            // We had an outstanding demand and where the first
                                            // upstream to produce an element so we can forward it to
                                            // the downstream
                                            continuation.resume(returning: element)

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
                                        case let .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                                            downstreamContinuation,
                                            task,
                                            upstreamContinuations
                                        ):
                                            upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                                            task.cancel()

                                            downstreamContinuation.resume(returning: nil)

                                            break loop

                                        case let .cancelTaskAndUpstreamContinuations(
                                            task,
                                            upstreamContinuations
                                        ):
                                            upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }
                                            task.cancel()

                                            break loop
                                        case .none:

                                            break loop
                                        }
                                    }
                                }
                            }
                        }

                        do {
                            try await group.waitForAll()
                        } catch {
                            // One of the upstream sequences threw an error
                            let action = self.lock.withLock {
                                self.stateMachine.upstreamThrew(error)
                            }

                            switch action {
                            case let .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
                                downstreamContinuation,
                                error,
                                task,
                                upstreamContinuations
                            ):
                                upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }

                                task.cancel()

                                downstreamContinuation.resume(throwing: error)
                            case let .cancelTaskAndUpstreamContinuations(
                                task,
                                upstreamContinuations
                            ):
                                upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }

                                task.cancel()

                            case .none:
                                break
                            }

                            group.cancelAll()
                        }
                    }
                }

                // We need to inform our state machine that we started the Task
                self.stateMachine.taskStarted(task)
            }
        }
    }

    func iteratorDeinitialized() {
        let action = lock.withLock { self.stateMachine.iteratorDeinitialized() }

        switch action {
        case let .cancelTaskAndUpstreamContinuations(
            task,
            upstreamContinuations
        ):
            upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }

            task.cancel()

        case .none:
            break
        }
    }

    func next() async rethrows -> Element? {
        // We need to handle cancellation here because we are creating a continuation
        // and because we need to cancel the `Task` we created to consume the upstream
        try await withTaskCancellationHandler {
            self.lock.lock()
            let action = self.stateMachine.next()

            switch action {
            case let .returnElement(element):
                self.lock.unlock()

                return try element._rethrowGet()

            case .returnNil:
                self.lock.unlock()
                return nil

            case let .throwError(error):
                self.lock.unlock()
                throw error

            case .suspendDownstreamTask:
                // It is safe to hold the lock across this method
                // since the closure is guaranteed to be run straight away
                return try await withUnsafeThrowingContinuation { continuation in
                    let action = self.stateMachine.next(for: continuation)
                    self.lock.unlock()

                    switch action {
                    case let .resumeUpstreamContinuations(upstreamContinuations):
                        // This is signalling the child tasks that are consuming the upstream
                        // sequences to signal demand.
                        upstreamContinuations.forEach { $0.resume(returning: ()) }
                    }
                }
            }
        } onCancel: {
            let action = self.lock.withLock { self.stateMachine.cancelled() }

            switch action {
            case let .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                downstreamContinuation,
                task,
                upstreamContinuations
            ):
                upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }

                task.cancel()

                downstreamContinuation.resume(returning: nil)

            case let .cancelTaskAndUpstreamContinuations(
                task,
                upstreamContinuations
            ):
                upstreamContinuations.forEach { $0.resume(throwing: CancellationError()) }

                task.cancel()

            case .none:
                break
            }
        }
    }
}


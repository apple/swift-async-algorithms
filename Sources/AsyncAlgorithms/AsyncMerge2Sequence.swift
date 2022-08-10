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

import DequeModule

/// Creates an asynchronous sequence of elements from two underlying asynchronous sequences
public func merge<Base1: AsyncSequence, Base2: AsyncSequence>(_ base1: Base1, _ base2: Base2) -> AsyncMerge2Sequence<Base1, Base2>
    where
    Base1.Element == Base2.Element,
    Base1: Sendable, Base2: Sendable,
    Base1.Element: Sendable
{
    return AsyncMerge2Sequence(base1, base2)
}

/// An ``Swift/AsyncSequence`` that takes two upstream ``Swift/AsyncSequence``s and combines their elements.
public struct AsyncMerge2Sequence<
    Base1: AsyncSequence,
    Base2: AsyncSequence
>: Sendable where
    Base1.Element == Base2.Element,
    Base1: Sendable, Base2: Sendable,
    Base1.Element: Sendable
{
    public typealias Element = Base1.Element

    /// This class is needed to hook the deinit to observe once all references to the ``AsyncMerge2Sequence`` are dropped.
    ///
    /// If we get move-only types we should be able to drop this class and use the `deinit` of the ``AsyncMerge2Sequence`` struct itself.
    ///
    /// - Important: This is safe to be unchecked ``Sendable`` since the `storage` is ``Sendable`` and `immutable`.
    final class InternalClass: @unchecked Sendable {
        fileprivate let storage: Storage

        fileprivate init(storage: Storage) {
            self.storage = storage
        }

        deinit {
            storage.sequenceDeinitialized()
        }
    }

    /// The internal class to hook the `deinit`.
    let internalClass: InternalClass

    /// The underlying storage
    fileprivate var storage: Storage {
        internalClass.storage
    }

    /// Initializes a new ``AsyncMerge2Sequence``.
    ///
    /// - Parameters:
    ///     - base1: The first upstream ``Swift/AsyncSequence``.
    ///     - base2: The second upstream ``Swift/AsyncSequence``.
    public init(
        _ base1: Base1,
        _ base2: Base2
    ) {
        let storage = Storage(
            base1: base1,
            base2: base2
        )
        internalClass = .init(storage: storage)
    }
}

extension AsyncMerge2Sequence: AsyncSequence {
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(storage: internalClass.storage)
    }
}

public extension AsyncMerge2Sequence {
    struct AsyncIterator: AsyncIteratorProtocol {
        /// This class is needed to hook the deinit to observe once all references to the ``AsyncIterator`` are dropped.
        ///
        /// If we get move-only types we should be able to drop this class and use the `deinit` of the ``AsyncIterator`` struct itself.
        ///
        /// - Important: This is safe to be unchecked ``Sendable`` since the `storage` is ``Sendable`` and `immutable`.
        final class InternalClass: @unchecked Sendable {
            private let storage: Storage

            fileprivate init(storage: Storage) {
                self.storage = storage
                self.storage.iteratorInitialized()
            }

            deinit {
                self.storage.iteratorDeinitialized()
            }

            func next() async throws -> Element? {
                try await storage.next()
            }
        }

        let internalClass: InternalClass

        fileprivate init(storage: Storage) {
            internalClass = InternalClass(storage: storage)
        }

        public mutating func next() async throws -> Element? {
            try await internalClass.next()
        }
    }
}

private extension AsyncMerge2Sequence {
    final class Storage: @unchecked Sendable {
        /// The lock that protects our state.
        private let lock = Lock.allocate()
        /// The state machine.
        private var stateMachine: StateMachine

        fileprivate init(
            base1: Base1,
            base2: Base2
        ) {
            stateMachine = .init(base1: base1, base2: base2)
        }

        deinit {
            self.lock.deinitialize()
        }

        fileprivate func sequenceDeinitialized() {
            lock.withLock { self.stateMachine.sequenceDeinitialized() }
        }

        fileprivate func iteratorInitialized() {
            lock.withLockVoid {
                let action = self.stateMachine.iteratorInitialized()

                // We are holding the lock while creating the `Task`
                // because we need to make sure that only one iterator is ever created
                // we could avoid holding the lock here by just introducing another state
                // in the state machine but that seems like an overkill
                switch action {
                case let .startTask(base1, base2):
                    // This creates a new `Task` that is iterating the upstream
                    // sequences. We must store it to cancel it at the right times.
                    let task = Task {
                        do {
                            try await withThrowingTaskGroup(of: Void.self) { group in
                                // For each upstream sequence we are adding a child task that
                                // is consuming the upstream sequence
                                group.addTask {
                                    var iterator1 = base1.makeAsyncIterator()

                                    // This is our upstream consumption loop
                                    loop: while true {
                                        // We are creating a continuation before requesting the next
                                        // element from upstream. This continuation is only resumed
                                        // if the downstream consumer called `next` to signal his demand.
                                        try await withCheckedThrowingContinuation { continuation in
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
                                        try await withCheckedThrowingContinuation { continuation in
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

                                try await group.waitForAll()
                            }
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
                        }
                    }

                    // We need to inform our state machine that we started the Task
                    self.stateMachine.taskStarted(task)
                }
            }
        }

        fileprivate func iteratorDeinitialized() {
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

        fileprivate func next() async throws -> Element? {
            // We need to handle cancellation here because we are creating a continuation
            // and because we need to cancel the `Task` we created to consume the upstream
            try await withTaskCancellationHandler {
                self.lock.lock()
                let action = self.stateMachine.next()

                switch action {
                case let .returnElement(element):
                    self.lock.unlock()
                    return element

                case .returnNil:
                    self.lock.unlock()
                    return nil

                case let .throwError(error):
                    self.lock.unlock()
                    throw error

                case .suspendDownstreamTask:
                    // It is safe to hold the lock across this method
                    // since the closure is guaranteed to be run straight away
                    return try await withCheckedThrowingContinuation { continuation in
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
}

extension AsyncMerge2Sequence {
    /// The state machine for `AsyncMerge2Sequence`
    struct StateMachine {
        private enum State {
            /// The initial state before a call to `makeAsyncIterator` happened.
            case initial(
                base1: Base1,
                base2: Base2
            )

            /// The state after `makeAsyncIterator` was called and we created our `Task` to consume the upstream.
            case merging(
                task: Task<Void, Never>,
                buffer: Deque<Element>,
                upstreamContinuations: [CheckedContinuation<Void, Error>],
                upstreamsFinished: Int,
                downstreamContinuation: CheckedContinuation<Element?, Error>?
            )

            /// The state once any of the upstream sequences threw an `Error`.
            case upstreamThrew(
                buffer: Deque<Element>,
                error: Error
            )

            /// The state once all upstream sequences finished or the downstream consumer stopped, i.e. by dropping all references
            /// or by getting their `Task` cancelled.
            case finished

            /// Internal state to avoid CoW.
            case modifying
        }

        /// The state machine's current state.
        private var state: State

        /// Initializes a new `StateMachine`.
        init(base1: Base1, base2: Base2) {
            state = .initial(
                base1: base1,
                base2: base2
            )
        }

        mutating func sequenceDeinitialized() {
            switch state {
            case .initial:
                // The references to the sequence were dropped before any iterator was ever created
                state = .finished

            case .merging, .upstreamThrew:
                // An iterator was created and we deinited the sequence.
                // This is an expected pattern and we just continue on normal.
                // Importantly since we are a unicast sequence no more iterators can be created
                break

            case .finished:
                // We are already finished so there is nothing left to clean up.
                // This is just the references dropping afterwards.
                break

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `iteratorInitialized()`.
        enum IteratorInitializedAction {
            /// Indicates that a new `Task` should be created that consumed the sequences.
            case startTask(Base1, Base2)
        }

        mutating func iteratorInitialized() -> IteratorInitializedAction {
            switch state {
            case let .initial(base1, base2):
                // This is the first iterator being created and we need to create our `Task`
                // that is consuming the upstream sequences.
                return .startTask(base1, base2)

            case .merging, .upstreamThrew, .finished:
                fatalError("merge allows only a single AsyncIterator to be created")

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `iteratorDeinitialized()`.
        enum IteratorDeinitializedAction {
            /// Indicates that the `Task` needs to be cancelled and
            /// all upstream continuations need to be resumed with a `CancellationError`.
            case cancelTaskAndUpstreamContinuations(
                task: Task<Void, Never>,
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
            /// Indicates that nothing should be done.
            case none
        }

        mutating func iteratorDeinitialized() -> IteratorDeinitializedAction {
            switch state {
            case .initial:
                // An iterator needs to be initialized before it can be deinitialized.
                preconditionFailure("Internal inconsistency")

            case .merging(_, _, _, _, .some):
                // An iterator was deinitialized while we have a suspended continuation.
                preconditionFailure("Internal inconsistency")

            case let .merging(task, _, upstreamContinuations, _, .none):
                // The iterator was dropped which signals that the consumer is finished.
                // We can transition to finished now and need to clean everything up.
                state = .finished

                return .cancelTaskAndUpstreamContinuations(
                    task: task,
                    upstreamContinuations: upstreamContinuations
                )

            case .upstreamThrew:
                // The iterator was dropped which signals that the consumer is finished.
                // We can transition to finished now. The cleanup already happened when we
                // transitioned to `upstreamThrew`.
                state = .finished

                return .none

            case .finished:
                // We are already finished so there is nothing left to clean up.
                // This is just the references dropping afterwards.
                return .none

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        mutating func taskStarted(_ task: Task<Void, Never>) {
            switch state {
            case .initial:
                // The user called `makeAsyncIterator` and we are starting the `Task`
                // to consume the upstream sequences
                state = .merging(
                    task: task,
                    buffer: .init(),
                    upstreamContinuations: [], // This should reserve capacity in the variadic generics case
                    upstreamsFinished: 0,
                    downstreamContinuation: nil
                )

            case .merging, .upstreamThrew, .finished:
                // We only a single iterator to be created so this must never happen.
                preconditionFailure("Invalid state")

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `childTaskSuspended()`.
        enum ChildTaskSuspendedAction {
            /// Indicates that the continuation should be resumed which will lead to calling `next` on the upstream.
            case resumeContinuation(
                upstreamContinuation: CheckedContinuation<Void, Error>
            )
            /// Indicates that the continuation should be resumed with an Error because another upstream sequence threw.
            case resumeContinuationWithError(
                upstreamContinuation: CheckedContinuation<Void, Error>,
                error: Error
            )
            /// Indicates that nothing should be done.
            case none
        }

        mutating func childTaskSuspended(_ continuation: CheckedContinuation<Void, Error>) -> ChildTaskSuspendedAction {
            switch state {
            case .initial:
                // Child tasks are only created after we transitioned to `merging`
                preconditionFailure("Invalid state")

            case .merging(_, _, _, _, .some):
                // We have outstanding demand so request the next element
                return .resumeContinuation(upstreamContinuation: continuation)

            case .merging(let task, let buffer, var upstreamContinuations, let upstreamsFinished, .none):
                // There is no outstanding demand from the downstream
                // so we are storing the continuation and resume it once there is demand.
                state = .modifying

                upstreamContinuations.append(continuation)

                state = .merging(
                    task: task,
                    buffer: buffer,
                    upstreamContinuations: upstreamContinuations,
                    upstreamsFinished: upstreamsFinished,
                    downstreamContinuation: nil
                )

                return .none

            case .upstreamThrew:
                // Another upstream already threw so we just need to throw from this continuation
                // which will end the consumption of the upstream.

                return .resumeContinuationWithError(
                    upstreamContinuation: continuation,
                    error: CancellationError()
                )

            case .finished:
                // Since cancellation is cooperative it might be that child tasks are still getting
                // suspended even though we already cancelled them. We must tolerate this and just resume
                // the continuation with an error.
                return .resumeContinuationWithError(
                    upstreamContinuation: continuation,
                    error: CancellationError()
                )

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `elementProduced()`.
        enum ElementProducedAction {
            /// Indicates that the downstream continuation should be resumed with the element.
            case resumeContinuation(
                downstreamContinuation: CheckedContinuation<Element?, Error>,
                element: Element
            )
            /// Indicates that nothing should be done.
            case none
        }

        mutating func elementProduced(_ element: Element) -> ElementProducedAction {
            switch state {
            case .initial:
                // Child tasks that are producing elements are only created after we transitioned to `merging`
                preconditionFailure("Invalid state")

            case let .merging(task, buffer, upstreamContinuations, upstreamsFinished, .some(downstreamContinuation)):
                // We produced an element and have an outstanding downstream continuation
                // this means we can go right ahead and resume the continuation with that element
                precondition(buffer.isEmpty, "We are holding a continuation so the buffer must be empty")

                state = .merging(
                    task: task,
                    buffer: buffer,
                    upstreamContinuations: upstreamContinuations,
                    upstreamsFinished: upstreamsFinished,
                    downstreamContinuation: nil
                )

                return .resumeContinuation(
                    downstreamContinuation: downstreamContinuation,
                    element: element
                )

            case .merging(let task, var buffer, let upstreamContinuations, let upstreamsFinished, .none):
                // There is not outstanding downstream continuation so we must buffer the element
                // This happens if we race our upstream sequences to produce elements
                // and the _losers_ are signalling their produced element
                state = .modifying

                buffer.append(element)

                state = .merging(
                    task: task,
                    buffer: buffer,
                    upstreamContinuations: upstreamContinuations,
                    upstreamsFinished: upstreamsFinished,
                    downstreamContinuation: nil
                )

                return .none

            case .upstreamThrew:
                // Another upstream already produced an error so we just drop the new element
                return .none

            case .finished:
                // Since cancellation is cooperative it might be that child tasks
                // are still producing elements after we finished.
                // We are just going to drop them since there is nothing we can do
                return .none

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `upstreamFinished()`.
        enum UpstreamFinishedAction {
            /// Indicates that the task and the upstream continuations should be cancelled.
            case cancelTaskAndUpstreamContinuations(
                task: Task<Void, Never>,
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
            /// Indicates that the downstream continuation should be resumed with `nil` and
            /// the task and the upstream continuations should be cancelled.
            case resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                downstreamContinuation: CheckedContinuation<Element?, Error>,
                task: Task<Void, Never>,
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
            /// Indicates that nothing should be done.
            case none
        }

        mutating func upstreamFinished() -> UpstreamFinishedAction {
            switch state {
            case .initial:
                preconditionFailure("Invalid state")

            case .merging(let task, let buffer, let upstreamContinuations, var upstreamsFinished, let .some(downstreamContinuation)):
                // One of the upstreams finished
                precondition(buffer.isEmpty, "We are holding a continuation so the buffer must be empty")

                // First we increment our counter of finished upstreams
                upstreamsFinished += 1

                // We should change the 2 when we get variadic generics
                if upstreamsFinished == 2 {
                    // All of our upstreams have finished and we can transition to finished now
                    // We also need to cancel the tasks and any outstanding continuations
                    state = .finished

                    return .resumeContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                        downstreamContinuation: downstreamContinuation,
                        task: task,
                        upstreamContinuations: upstreamContinuations
                    )
                } else {
                    // There are still upstreams that haven't finished so we are just storing our new
                    // counter of finished upstreams
                    state = .merging(
                        task: task,
                        buffer: buffer,
                        upstreamContinuations: upstreamContinuations,
                        upstreamsFinished: upstreamsFinished,
                        downstreamContinuation: downstreamContinuation
                    )

                    return .none
                }

            case .merging(let task, let buffer, let upstreamContinuations, var upstreamsFinished, .none):
                // First we increment our counter of finished upstreams
                upstreamsFinished += 1

                state = .merging(
                    task: task,
                    buffer: buffer,
                    upstreamContinuations: upstreamContinuations,
                    upstreamsFinished: upstreamsFinished,
                    downstreamContinuation: nil
                )

                if upstreamsFinished == 2 {
                    // All of our upstreams have finished; however, we are only transitioning to
                    // finished once our downstream calls `next` again.
                    return .cancelTaskAndUpstreamContinuations(
                        task: task,
                        upstreamContinuations: upstreamContinuations
                    )
                } else {
                    // There are still upstreams that haven't finished.
                    return .none
                }

            case .upstreamThrew:
                // Another upstream threw already so we can just ignore this finish
                return .none

            case .finished:
                // This is just everything finishing up, nothing to do here
                return .none

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `upstreamThrew()`.
        enum UpstreamThrewAction {
            /// Indicates that the task and the upstream continuations should be cancelled.
            case cancelTaskAndUpstreamContinuations(
                task: Task<Void, Never>,
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
            /// Indicates that the downstream continuation should be resumed with the `error` and
            /// the task and the upstream continuations should be cancelled.
            case resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
                downstreamContinuation: CheckedContinuation<Element?, Error>,
                error: Error,
                task: Task<Void, Never>,
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
            /// Indicates that nothing should be done.
            case none
        }

        mutating func upstreamThrew(_ error: Error) -> UpstreamThrewAction {
            switch state {
            case .initial:
                preconditionFailure("Invalid state")

            case let .merging(task, buffer, upstreamContinuations, _, .some(downstreamContinuation)):
                // An upstream threw an error and we have a downstream continuation.
                // We just need to resume the downstream continuation with the error and cancel everything
                precondition(buffer.isEmpty, "We are holding a continuation so the buffer must be empty")

                // We can transition to finished right away because we are returning the error
                state = .finished

                return .resumeContinuationWithErrorAndCancelTaskAndUpstreamContinuations(
                    downstreamContinuation: downstreamContinuation,
                    error: error,
                    task: task,
                    upstreamContinuations: upstreamContinuations
                )

            case let .merging(task, buffer, upstreamContinuations, _, .none):
                // An upstream threw an error and we don't have a downstream continuation.
                // We need to store the error and wait for the downstream to consume the
                // rest of the buffer and the error. However, we can already cancel the task
                // and the other upstream continuations since we won't need any more elements.
                state = .upstreamThrew(
                    buffer: buffer,
                    error: error
                )
                return .cancelTaskAndUpstreamContinuations(
                    task: task,
                    upstreamContinuations: upstreamContinuations
                )

            case .upstreamThrew:
                // Another upstream threw already so we can just ignore this error
                return .none

            case .finished:
                // This is just everything finishing up, nothing to do here
                return .none

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `cancelled()`.
        enum CancelledAction {
            /// Indicates that the downstream continuation needs to be resumed and
            /// task and the upstream continuations should be cancelled.
            case resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                downstreamContinuation: CheckedContinuation<Element?, Error>,
                task: Task<Void, Never>,
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
            /// Indicates that the task and the upstream continuations should be cancelled.
            case cancelTaskAndUpstreamContinuations(
                task: Task<Void, Never>,
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
            /// Indicates that nothing should be done.
            case none
        }

        mutating func cancelled() -> CancelledAction {
            switch state {
            case .initial:
                // Since we are transitioning to `merging` before we return from `makeAsyncIterator`
                // this can never happen
                preconditionFailure("Invalid state")

            case let .merging(task, _, upstreamContinuations, _, .some(downstreamContinuation)):
                // The downstream Task got cancelled so we need to cancel our upstream Task
                // and resume all continuations. We can also transition to finished.
                state = .finished

                return .resumeDownstreamContinuationWithNilAndCancelTaskAndUpstreamContinuations(
                    downstreamContinuation: downstreamContinuation,
                    task: task,
                    upstreamContinuations: upstreamContinuations
                )

            case let .merging(task, _, upstreamContinuations, _, .none):
                // The downstream Task got cancelled so we need to cancel our upstream Task
                // and resume all continuations. We can also transition to finished.
                state = .finished

                return .cancelTaskAndUpstreamContinuations(
                    task: task,
                    upstreamContinuations: upstreamContinuations
                )

            case .upstreamThrew:
                // An upstream already threw  and we cancelled everything already.
                // We can just transition to finished now
                state = .finished

                return .none

            case .finished:
                // We are already finished so nothing to do here:
                state = .finished

                return .none

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `next()`.
        enum NextAction {
            /// Indicates that the `element` should be returned.
            case returnElement(Element)
            /// Indicates that `nil` should be returned.
            case returnNil
            /// Indicates that the `error` should be thrown.
            case throwError(Error)
            /// Indicates that the downstream task should be suspended.
            case suspendDownstreamTask
        }

        mutating func next() -> NextAction {
            switch state {
            case .initial:
                preconditionFailure("Invalid state")

            case .merging(_, _, _, _, .some):
                // We have multiple AsyncIterators iterating the sequence
                preconditionFailure("This should never happen since we only allow a single Iterator to be created")

            case .merging(let task, var buffer, let upstreamContinuations, let upstreamsFinished, .none):
                state = .modifying

                if let element = buffer.popFirst() {
                    // We have an element buffered already so we can just return that.
                    state = .merging(
                        task: task,
                        buffer: buffer,
                        upstreamContinuations: upstreamContinuations,
                        upstreamsFinished: upstreamsFinished,
                        downstreamContinuation: nil
                    )

                    return .returnElement(element)
                } else {
                    // There was nothing in the buffer so we have to suspend the downstream task
                    state = .merging(
                        task: task,
                        buffer: buffer,
                        upstreamContinuations: upstreamContinuations,
                        upstreamsFinished: upstreamsFinished,
                        downstreamContinuation: nil
                    )

                    return .suspendDownstreamTask
                }

            case .upstreamThrew(var buffer, let error):
                state = .modifying

                if let element = buffer.popFirst() {
                    // There was still a left over element that we need to return
                    state = .upstreamThrew(
                        buffer: buffer,
                        error: error
                    )

                    return .returnElement(element)
                } else {
                    // The buffer is empty and we can now throw the error
                    // that an upstream produced
                    state = .finished

                    return .throwError(error)
                }

            case .finished:
                // We are already finished so we are just returning `nil`
                return .returnNil

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }

        /// Actions returned by `next(for)`.
        enum NextForAction {
            /// Indicates that the upstream continuations should be resumed to demand new elements.
            case resumeUpstreamContinuations(
                upstreamContinuations: [CheckedContinuation<Void, Error>]
            )
        }

        mutating func next(for continuation: CheckedContinuation<Element?, Error>) -> NextForAction {
            switch state {
            case .initial,
                 .merging(_, _, _, _, .some),
                 .upstreamThrew,
                 .finished:
                // All other states are handled by `next` already so we should never get in here with
                // any of those
                preconditionFailure("Invalid state")

            case let .merging(task, buffer, upstreamContinuations, upstreamsFinished, .none):
                // We suspended the task and need signal the upstreams
                state = .merging(
                    task: task,
                    buffer: buffer,
                    upstreamContinuations: [], // TODO: don't alloc new array here
                    upstreamsFinished: upstreamsFinished,
                    downstreamContinuation: continuation
                )

                return .resumeUpstreamContinuations(
                    upstreamContinuations: upstreamContinuations
                )

            case .modifying:
                preconditionFailure("Invalid state")
            }
        }
    }
}

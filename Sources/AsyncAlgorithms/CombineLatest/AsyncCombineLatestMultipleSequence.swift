//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Creates an asynchronous sequence that combines the latest values from multiple ``AsyncSequence`` with the same element type
/// by emitting an array of the values.
///
/// The new asynchronous sequence only emits a value whenever any of the base ``AsyncSequence``s
/// emit a value (so long as each of the bases have emitted at least one value).
///
/// - Important: It finishes when one of the bases finishes before emitting any value or when all bases finished.
///
/// - Throws: It throws when one of the bases throws.
///
/// - Note: This function requires the return type to be the same for all ``AsyncSequence``.
public func combineLatest<Sequence: AsyncSequence, ElementOfResult: Sendable>(_ sequences: [Sequence]) -> AsyncThrowingStream<[ElementOfResult], Error> where Sequence.Element == ElementOfResult, Sequence: Sendable {
    AsyncCombineLatestMultipleSequence(sequences: sequences).stream
}

/// Creates an asynchronous sequence that combines the latest values from multiple ``AsyncSequence`` with the same element type
/// by emitting an array of the values.
///
/// The new asynchronous sequence only emits a value whenever any of the base ``AsyncSequence``s
/// emit a value (so long as each of the bases have emitted at least one value).
///
/// - Important: It finishes when one of the bases finishes before emitting any value or when all bases finished.
///
/// - Throws: It throws when one of the bases throws.
///
/// - Note: This function requires the return type to be the same for all ``AsyncSequence``.
public func combineLatest<Sequence: AsyncSequence, ElementOfResult: Sendable>(_ sequences: Sequence...) -> AsyncThrowingStream<[ElementOfResult], Error> where Sequence.Element == ElementOfResult, Sequence: Sendable {
    AsyncCombineLatestMultipleSequence(sequences: sequences).stream
}

fileprivate final class AsyncCombineLatestMultipleSequence<Sequence: AsyncSequence, ElementOfResult: Sendable>: Sendable where Sequence.Element == ElementOfResult, Sequence: Sendable {

    private let results: ManagedCriticalState<[State]>
    private let continuation: AsyncThrowingStream<[ElementOfResult], Error>.Continuation

    fileprivate let stream: AsyncThrowingStream<[ElementOfResult], Error>

    fileprivate init(sequences: [Sequence]) {
        self.results = .init(
            Array(
                repeating: State.initial,
                count: sequences.count
            )
        )

        (self.stream, self.continuation) = AsyncThrowingStream<[ElementOfResult], Error>.makeStream()

        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                for (index, sequence) in sequences.enumerated() {
                    group.addTask {
                        do {
                            var lastKnownValue: ElementOfResult?
                            for try await value in sequence {
                                self.set(state: .succeeded(value), at: index)
                                lastKnownValue = value
                            }
                            self.set(state: .finished(lastKnownValue: lastKnownValue), at: index)
                        } catch {
                            self.set(state: .failed(error), at: index)
                        }
                    }
                }
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

// MARK: - Private helpers

private extension AsyncCombineLatestMultipleSequence {

    func set(state: State, at index: Int) {
        results.withCriticalRegion { array in
            array[index] = state

            var allFinished = true
            var latestResults: [ElementOfResult] = []
            latestResults.reserveCapacity(array.count)

            for state in array {
                switch state {
                    case .initial:
                        // Only emit updates when all have value.
                        return

                    case .succeeded(let elementOfResult):
                        latestResults.append(elementOfResult)
                        allFinished = false

                    case .failed(let error):
                        continuation.finish(throwing: error)
                        return

                    case .finished(let lastKnownValue):
                        if let lastKnownValue {
                            latestResults.append(lastKnownValue)
                        } else {
                            // If `lastKnownValue` is nil,
                            // that means the async sequence finished before emitting any value.
                            // And we'll never be able to complete the entire array.
                            continuation.finish()
                            return
                        }
                }
            }

            if allFinished {
                continuation.finish()
            } else if case .succeeded = state {
                continuation.yield(latestResults)
            }
        }
    }
}

// MARK: - Type definitions

private extension AsyncCombineLatestMultipleSequence {

    enum State {
        case initial
        case succeeded(ElementOfResult)
        case failed(Error)
        case finished(lastKnownValue: ElementOfResult?)
    }
}

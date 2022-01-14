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

import AsyncAlgorithms
import Foundation
import XCTest

// TODO: Update all of these to use Clock and Duration and remove Foundation/ProcessInfo dependencies.
public struct InfiniteTimedSingleValueSequence<Value: Sendable>: AsyncSequence, Sendable {
    public typealias Element = Value
    let value: Value
    let duration: Double

    public struct AsyncIterator : AsyncIteratorProtocol, Sendable {

        @usableFromInline
        let value: Value

        @usableFromInline
        let duration: Double

        @usableFromInline
        var start: Double? = nil

        @inlinable
        public mutating func next() async throws -> Element? {
            if start == nil {
                start = ProcessInfo.processInfo.systemUptime
            }
            guard ProcessInfo.processInfo.systemUptime - start! <= duration else {
                return nil
            }
            return value
        }
    }
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(value: value, duration: duration)
    }
}

public struct InfiniteTimedSequence<Source : AsyncSequence>: AsyncSequence, Sendable where Source: Sendable, Source.AsyncIterator: Sendable {
    public typealias Element = Source.Element
    let sequence: Source
    let duration: Double

    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {

        @usableFromInline
        var iterator: Source.AsyncIterator

        @usableFromInline
        let duration: Double

        @usableFromInline
        var start: Double? = nil

        @inlinable
        public mutating func next() async rethrows -> Element? {
            if start == nil {
                start = ProcessInfo.processInfo.systemUptime
            }
            guard ProcessInfo.processInfo.systemUptime - start! <= duration else {
                return nil
            }
            return try await iterator.next()
        }
    }
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(iterator: sequence.makeAsyncIterator(), duration: duration)
    }
}

final class _ThroughputMetric: NSObject, XCTMetric, @unchecked Sendable {
    var eventCount = 0

    override init() { }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp, to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        return [XCTPerformanceMeasurement(identifier: "com.swift.AsyncAlgorithms.Throughput", displayName: "Throughput", doubleValue: Double(eventCount) / (endTime.date.timeIntervalSinceReferenceDate - startTime.date.timeIntervalSinceReferenceDate), unitSymbol: " Events/sec")]
    }

    func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    func willBeginMeasuring() {
        eventCount = 0
    }
    func didStopMeasuring() { }
}

extension XCTestCase {
    public func measureSequenceThroughput<S: AsyncSequence, Output>( output: @autoclosure () -> Output, _ sequenceBuilder: (InfiniteTimedSingleValueSequence<Output>) -> S) async where S: Sendable {
        let metric = _ThroughputMetric()

        measure(metrics: [metric]) {
            let infSeq = InfiniteTimedSingleValueSequence(value: output(), duration: 1.0)
            let seq = sequenceBuilder(infSeq)

            let exp = self.expectation(description: "Finished")
            Task<Int, Error> {
                var eventCount = 0
                for try await _ in seq {
                    eventCount += 1
                }
                metric.eventCount = eventCount
                exp.fulfill()
                return eventCount
            }
            self.wait(for: [exp], timeout: 2.0)
        }
    }

    public func measureSequenceThroughput<S: AsyncSequence, Source: AsyncSequence>( source: Source, _ sequenceBuilder: (InfiniteTimedSequence<Source>) -> S) async where S: Sendable, Source: Sendable {
        let metric = _ThroughputMetric()

        measure(metrics: [metric]) {
            let infSeq = InfiniteTimedSequence(sequence: source, duration: 1.0)
            let seq = sequenceBuilder(infSeq)

            let exp = self.expectation(description: "Finished")
            Task<Int, Error> {
                var eventCount = 0
                for try await _ in seq {
                    eventCount += 1
                }
                metric.eventCount = eventCount
                exp.fulfill()
                return eventCount
            }
            self.wait(for: [exp], timeout: 2.0)
        }
    }
}

final class TestMeasurements: XCTestCase {
    struct PassthroughSequence<S: AsyncSequence> : AsyncSequence, Sendable where S : Sendable, S.AsyncIterator : Sendable {
        typealias Element = S.Element

        struct AsyncIterator : AsyncIteratorProtocol, Sendable {

            @usableFromInline
            var base : S.AsyncIterator

            @inlinable
            mutating func next() async throws -> Element? {
                return try await base.next()
            }
        }

        let base : S
        func makeAsyncIterator() -> AsyncIterator {
            .init(base: base.makeAsyncIterator())
        }
    }

    public func testThroughputTesting() async {
        await self.measureSequenceThroughput(output: 1) {
            PassthroughSequence(base: $0)
        }
    }
}

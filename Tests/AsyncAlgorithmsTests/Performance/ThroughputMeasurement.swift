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

#if canImport(Darwin)
public struct InfiniteAsyncSequence<Value: Sendable>: AsyncSequence, Sendable {
  public typealias Element = Value
  let value: Value

  public struct AsyncIterator: AsyncIteratorProtocol, Sendable {

    @usableFromInline
    let value: Value

    @inlinable
    public mutating func next() async throws -> Element? {
      guard !Task.isCancelled else {
        return nil
      }
      return value
    }
  }
  public func makeAsyncIterator() -> AsyncIterator {
    return AsyncIterator(value: value)
  }
}

final class _ThroughputMetric: NSObject, XCTMetric, @unchecked Sendable {
  var eventCount = 0

  override init() {}

  func reportMeasurements(
    from startTime: XCTPerformanceMeasurementTimestamp,
    to endTime: XCTPerformanceMeasurementTimestamp
  ) throws -> [XCTPerformanceMeasurement] {
    return [
      XCTPerformanceMeasurement(
        identifier: "com.swift.AsyncAlgorithms.Throughput",
        displayName: "Throughput",
        doubleValue: Double(eventCount)
          / (endTime.date.timeIntervalSinceReferenceDate - startTime.date.timeIntervalSinceReferenceDate),
        unitSymbol: " Events/sec",
        polarity: .prefersLarger
      )
    ]
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  func willBeginMeasuring() {
    eventCount = 0
  }
  func didStopMeasuring() {}
}

extension XCTestCase {
  public func measureChannelThroughput<Output: Sendable>(output: @Sendable @escaping @autoclosure () -> Output) async {
    let metric = _ThroughputMetric()
    let sampleTime: Double = 0.1

    measure(metrics: [metric]) {
      let channel = AsyncChannel<Output>()

      let exp = self.expectation(description: "Finished")
      let iterTask = Task<Int, Error> {
        var eventCount = 0
        for try await _ in channel {
          eventCount += 1
        }
        metric.eventCount = eventCount
        exp.fulfill()
        return eventCount
      }
      let sendTask = Task<Void, Never> {
        while !Task.isCancelled {
          await channel.send(output())
        }
      }
      usleep(UInt32(sampleTime * Double(USEC_PER_SEC)))
      iterTask.cancel()
      sendTask.cancel()
      self.wait(for: [exp], timeout: sampleTime * 2)
    }
  }

  public func measureThrowingChannelThroughput<Output: Sendable>(
    output: @Sendable @escaping @autoclosure () -> Output
  ) async {
    let metric = _ThroughputMetric()
    let sampleTime: Double = 0.1

    measure(metrics: [metric]) {
      let channel = AsyncThrowingChannel<Output, Error>()

      let exp = self.expectation(description: "Finished")
      let iterTask = Task<Int, Error> {
        var eventCount = 0
        for try await _ in channel {
          eventCount += 1
        }
        metric.eventCount = eventCount
        exp.fulfill()
        return eventCount
      }
      let sendTask = Task<Void, Never> {
        while !Task.isCancelled {
          await channel.send(output())
        }
      }
      usleep(UInt32(sampleTime * Double(USEC_PER_SEC)))
      iterTask.cancel()
      sendTask.cancel()
      self.wait(for: [exp], timeout: sampleTime * 2)
    }
  }

  public func measureSequenceThroughput<S: AsyncSequence, Output>(
    output: @autoclosure () -> Output,
    _ sequenceBuilder: (InfiniteAsyncSequence<Output>) -> S
  ) async where S: Sendable {
    let metric = _ThroughputMetric()
    let sampleTime: Double = 0.1

    measure(metrics: [metric]) {
      let infSeq = InfiniteAsyncSequence(value: output())
      let seq = sequenceBuilder(infSeq)

      let exp = self.expectation(description: "Finished")
      let iterTask = Task<Int, Error> {
        var eventCount = 0
        for try await _ in seq {
          eventCount += 1
        }
        metric.eventCount = eventCount
        exp.fulfill()
        return eventCount
      }
      usleep(UInt32(sampleTime * Double(USEC_PER_SEC)))
      iterTask.cancel()
      self.wait(for: [exp], timeout: sampleTime * 2)
    }
  }

  public func measureSequenceThroughput<S: AsyncSequence, Output>(
    firstOutput: @autoclosure () -> Output,
    secondOutput: @autoclosure () -> Output,
    _ sequenceBuilder: (InfiniteAsyncSequence<Output>, InfiniteAsyncSequence<Output>) -> S
  ) async where S: Sendable {
    let metric = _ThroughputMetric()
    let sampleTime: Double = 0.1

    measure(metrics: [metric]) {
      let firstInfSeq = InfiniteAsyncSequence(value: firstOutput())
      let secondInfSeq = InfiniteAsyncSequence(value: secondOutput())
      let seq = sequenceBuilder(firstInfSeq, secondInfSeq)

      let exp = self.expectation(description: "Finished")
      let iterTask = Task<Int, Error> {
        var eventCount = 0
        for try await _ in seq {
          eventCount += 1
        }
        metric.eventCount = eventCount
        exp.fulfill()
        return eventCount
      }
      usleep(UInt32(sampleTime * Double(USEC_PER_SEC)))
      iterTask.cancel()
      self.wait(for: [exp], timeout: sampleTime * 2)
    }
  }

  public func measureSequenceThroughput<S: AsyncSequence, Output>(
    firstOutput: @autoclosure () -> Output,
    secondOutput: @autoclosure () -> Output,
    thirdOutput: @autoclosure () -> Output,
    _ sequenceBuilder: (InfiniteAsyncSequence<Output>, InfiniteAsyncSequence<Output>, InfiniteAsyncSequence<Output>)
      -> S
  ) async where S: Sendable {
    let metric = _ThroughputMetric()
    let sampleTime: Double = 0.1

    measure(metrics: [metric]) {
      let firstInfSeq = InfiniteAsyncSequence(value: firstOutput())
      let secondInfSeq = InfiniteAsyncSequence(value: secondOutput())
      let thirdInfSeq = InfiniteAsyncSequence(value: thirdOutput())
      let seq = sequenceBuilder(firstInfSeq, secondInfSeq, thirdInfSeq)

      let exp = self.expectation(description: "Finished")
      let iterTask = Task<Int, Error> {
        var eventCount = 0
        for try await _ in seq {
          eventCount += 1
        }
        metric.eventCount = eventCount
        exp.fulfill()
        return eventCount
      }
      usleep(UInt32(sampleTime * Double(USEC_PER_SEC)))
      iterTask.cancel()
      self.wait(for: [exp], timeout: sampleTime * 2)
    }
  }

  public func measureSequenceThroughput<S: AsyncSequence, Source: AsyncSequence>(
    source: Source,
    _ sequenceBuilder: (Source) -> S
  ) async where S: Sendable, Source: Sendable {
    let metric = _ThroughputMetric()
    let sampleTime: Double = 0.1

    measure(metrics: [metric]) {
      let infSeq = source
      let seq = sequenceBuilder(infSeq)

      let exp = self.expectation(description: "Finished")
      let iterTask = Task<Int, Error> {
        var eventCount = 0
        for try await _ in seq {
          eventCount += 1
        }
        metric.eventCount = eventCount
        exp.fulfill()
        return eventCount
      }
      usleep(UInt32(sampleTime * Double(USEC_PER_SEC)))
      iterTask.cancel()
      self.wait(for: [exp], timeout: sampleTime * 2)
    }
  }
}

final class TestMeasurements: XCTestCase {
  struct PassthroughSequence<S: AsyncSequence>: AsyncSequence, Sendable where S: Sendable, S.AsyncIterator: Sendable {
    typealias Element = S.Element

    struct AsyncIterator: AsyncIteratorProtocol, Sendable {

      @usableFromInline
      var base: S.AsyncIterator

      @inlinable
      mutating func next() async throws -> Element? {
        return try await base.next()
      }
    }

    let base: S
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
#endif

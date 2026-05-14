//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming && compiler(>=6.4)

import AsyncStreaming
import BasicContainers
import ContainersPreview
import DequeModule
import Testing

@Suite(.serialized)
struct MultiProducerSingleConsumerAsyncChannelTests {
  // MARK: - AsyncReader.read

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readReturnsAllBufferedElementsInOrder() async throws {
    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 10)
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 5)
      for v in [1, 2, 3, 4, 5] { writeBuffer.append(v) }
      try await source.write(buffer: &writeBuffer)

      try await channel.read { buffer, _ in
        #expect(buffer.count == 5)
        var consumer = buffer.consumeAll()
        var actual: [Int] = []
        while let v = consumer.next() { actual.append(v) }
        #expect(actual == [1, 2, 3, 4, 5])
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readSuspendsUntilElementArrives() async throws {
    try await withThrowingTaskGroup(of: [Int].self) { group in
      try await MultiProducerSingleConsumerAsyncChannel.withChannel(
        of: Int.self,
        backpressureStrategy: .watermark(low: 2, high: 4)
      ) { channel, source in
        var channel = channel
        var source = source
        group.addTask {
          var collected: [Int] = []
          try await channel.read { buffer, _ in
            var consumer = buffer.consumeAll()
            while let v = consumer.next() { collected.append(v) }
          }
          return collected
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        var writeBuffer = UniqueArray<Int>(minimumCapacity: 1)
        writeBuffer.append(42)
        try await source.write(buffer: &writeBuffer)
        let result = try await group.next()
        #expect(result == [42])
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readReturnsEmptyBufferOnEOSAfterFinish() async throws {
    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 1)
      writeBuffer.append(1)
      try await source.write(buffer: &writeBuffer)
      source.finish()

      try await channel.read { buffer, _ in
        #expect(buffer.count == 1)
        buffer.removeAll()
      }
      var sawEmpty = false
      try await channel.read { buffer, _ in
        sawEmpty = buffer.count == 0
      }
      #expect(sawEmpty)
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readThrowsFailureAfterFinishWithError() async throws {
    struct TestError: Error, Equatable {}

    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      throwing: TestError.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 1)
      writeBuffer.append(1)
      try await source.write(buffer: &writeBuffer)
      source.finish(throwing: TestError())

      // First read still delivers the buffered element.
      try? await channel.read { buffer, _ in
        #expect(buffer.count == 1)
        buffer.removeAll()
      }
      // Second read throws the queued failure through EitherError.first.
      do {
        try await channel.read { _, _ in }
        Issue.record("expected throw")
      } catch let EitherError<EitherError<TestError, CancellationError>, Never>.first(.first(err)) {
        #expect(err == TestError())
      } catch {
        Issue.record("unexpected error: \(error)")
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readBodyErrorsWrappedInSecond() async throws {
    struct BodyError: Error, Equatable {}

    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 1)
      writeBuffer.append(1)
      try await source.write(buffer: &writeBuffer)

      do {
        try await channel.read { _, _ throws(BodyError) in
          throw BodyError()
        }
        Issue.record("expected throw")
      } catch let EitherError<EitherError<Never, CancellationError>, BodyError>.second(err) {
        #expect(err == BodyError())
      } catch {
        Issue.record("unexpected error: \(error)")
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readPartialConsumptionRemainsVisibleOnNextRead() async throws {
    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 10)
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 5)
      for v in [1, 2, 3, 4, 5] { writeBuffer.append(v) }
      try await source.write(buffer: &writeBuffer)

      try await channel.read { buffer, _ in
        var consumer = buffer.consumeFirst(2)
        #expect(consumer.next() == 1)
        #expect(consumer.next() == 2)
      }

      try await channel.read { buffer, _ in
        #expect(buffer.count == 3)
        var consumer = buffer.consumeAll()
        var collected: [Int] = []
        while let v = consumer.next() { collected.append(v) }
        #expect(collected == [3, 4, 5])
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readResumesSuspendedProducersWhenWaterLevelDrops() async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      try await MultiProducerSingleConsumerAsyncChannel.withChannel(
        of: Int.self,
        backpressureStrategy: .watermark(low: 2, high: 4)
      ) { channel, source in
        var channel = channel
        var source = source

        group.addTask {
          // Fill to exactly the high watermark - this write suspends.
          var firstBatch = UniqueArray<Int>(minimumCapacity: 4)
          for v in [1, 2, 3, 4] { firstBatch.append(v) }
          try await source.write(buffer: &firstBatch)
          // Then send the 5th element once backpressure is relieved.
          var secondBatch = UniqueArray<Int>(minimumCapacity: 1)
          secondBatch.append(5)
          try await source.write(buffer: &secondBatch)
        }

        // Wait until the producer suspends after appending the first batch.
        try await Task.sleep(nanoseconds: 10_000_000)
        // Drain the buffered elements - the water level drops below the low
        // watermark and wakes the producer.
        try await channel.read { buffer, _ in
          #expect(buffer.count == 4)
          buffer.removeAll()
        }
        try await group.next()
        // The 5th element produced after the producer resumed.
        try await channel.read { buffer, _ in
          #expect(buffer.count == 1)
          buffer.removeAll()
        }
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readWaterLevelForElementCalledPerElementInBatch() async throws {
    nonisolated(unsafe) var callCount = 0
    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(
        low: 5,
        high: 100,
        waterLevelForElement: { _ in
          callCount += 1
          return 1
        }
      )
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 4)
      for v in [1, 2, 3, 4] { writeBuffer.append(v) }
      try await source.write(buffer: &writeBuffer)
      let afterSend = callCount

      try await channel.read { buffer, _ in
        #expect(buffer.count == 4)
        buffer.removeAll()
      }
      // Called once per element on send, once per element on consume.
      #expect(afterSend == 4)
      #expect(callCount == 8)
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readBufferIsReusedAcrossReads() async throws {
    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 100)
    ) { channel, source in
      var channel = channel
      var source = source

      // The channel alternates two internal buffers across reads (swap
      // design): on each read the producer-side buffer is handed to the
      // reader and the previously-handed-back buffer becomes the new
      // producer-side. Verify that two reads of the same size land on
      // matching capacities, i.e. the channel is reusing storage rather than
      // allocating a fresh buffer per read.
      var firstBatch = UniqueArray<Int>(minimumCapacity: 10)
      for v in 0..<10 { firstBatch.append(v) }
      try await source.write(buffer: &firstBatch)
      nonisolated(unsafe) var firstCapacity = 0
      try await channel.read { buffer, _ in
        firstCapacity = buffer.capacity
        var c = buffer.consumeAll()
        while c.next() != nil {}
      }
      #expect(firstCapacity >= 10)

      // Second read of the same size lands on the alternate buffer; after
      // the first round trip both buffers have grown to at least the
      // workload's capacity, so this read should see at least as much.
      var secondBatch = UniqueArray<Int>(minimumCapacity: 10)
      for v in 0..<10 { secondBatch.append(v) }
      try await source.write(buffer: &secondBatch)
      try await channel.read { buffer, _ in
        #expect(buffer.capacity >= firstCapacity)
        var c = buffer.consumeAll()
        while c.next() != nil {}
      }

      // A third read of the same size should reuse the original buffer
      // (capacity matches first read's exactly).
      var thirdBatch = UniqueArray<Int>(minimumCapacity: 10)
      for v in 0..<10 { thirdBatch.append(v) }
      try await source.write(buffer: &thirdBatch)
      try await channel.read { buffer, _ in
        #expect(buffer.capacity == firstCapacity)
        var c = buffer.consumeAll()
        while c.next() != nil {}
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readDeliversFinalElementOnFinish() async throws {
    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 8)
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 3)
      for v in [1, 2, 3] { writeBuffer.append(v) }
      try await source.write(buffer: &writeBuffer)
      source.finish()

      nonisolated(unsafe) var collected: [Int] = []
      var sawFinal = false
      var done = false
      while !done {
        try await channel.read { buffer, finalElement in
          var c = buffer.consumeAll()
          while let v = c.next() { collected.append(v) }
          if finalElement != nil {
            sawFinal = true
            done = true
          }
        }
      }
      #expect(collected == [1, 2, 3])
      #expect(sawFinal)
    }
  }

  // MARK: - CallerAsyncWriter.write

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writeAppendsAllElementsAndClearsBuffer() async throws {
    try await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 100)
    ) { channel, source in
      var channel = channel
      var source = source

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 5)
      writeBuffer.append(10)
      writeBuffer.append(20)
      writeBuffer.append(30)

      try await source.write(buffer: &writeBuffer)
      #expect(writeBuffer.count == 0, "write should drain the caller's buffer")

      try await channel.read { buffer, _ in
        #expect(buffer.count == 3)
        var c = buffer.consumeAll()
        var collected: [Int] = []
        while let v = c.next() { collected.append(v) }
        #expect(collected == [10, 20, 30])
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writeAfterFinishThrows() async throws {
    await MultiProducerSingleConsumerAsyncChannel.withChannel(
      of: Int.self,
      backpressureStrategy: .watermark(low: 1, high: 4)
    ) { channel, source in
      var channel = channel
      var source = source

      // Keep an additional source around so we can attempt a write after the
      // channel has been finished by consuming the first source.
      var extraSource = source.clone()
      source.finish()

      var writeBuffer = UniqueArray<Int>(minimumCapacity: 1)
      writeBuffer.append(1)

      do {
        try await extraSource.write(buffer: &writeBuffer)
        Issue.record("expected throw")
      } catch is MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError {
        // expected
      } catch {
        Issue.record("unexpected error: \(error)")
      }

      // Drain anything still buffered before exiting the scope.
      try? await channel.read { _, _ in }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writeSuspendsOnBackpressureAndResumesAfterRead() async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      try await MultiProducerSingleConsumerAsyncChannel.withChannel(
        of: Int.self,
        backpressureStrategy: .watermark(low: 1, high: 2)
      ) { channel, source in
        var channel = channel
        var source = source

        group.addTask {
          // Reader drains until EOS.
          while true {
            var done = false
            try await channel.read { buffer, _ in
              if buffer.count == 0 {
                done = true
              } else {
                buffer.removeAll()
              }
            }
            if done { break }
          }
        }

        var buf = UniqueArray<Int>(minimumCapacity: 4)
        for i in 0..<4 { buf.append(i) }
        try await source.write(buffer: &buf)
        source.finish()
        try await group.next()
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writeReadRoundtripPreservesOrder() async throws {
    let total = 100
    try await withThrowingTaskGroup(of: Void.self) { group in
      try await MultiProducerSingleConsumerAsyncChannel.withChannel(
        of: Int.self,
        backpressureStrategy: .watermark(low: 10, high: 50)
      ) { channel, source in
        var channel = channel
        var source = source

        group.addTask {
          nonisolated(unsafe) var collected: [Int] = []
          var done = false
          while !done {
            try await channel.read { buffer, _ in
              if buffer.count == 0 {
                done = true
              } else {
                var c = buffer.consumeAll()
                while let v = c.next() { collected.append(v) }
              }
            }
          }
          #expect(collected == Array(0..<total))
        }
        for start in stride(from: 0, to: total, by: 10) {
          var buf = UniqueArray<Int>(minimumCapacity: 10)
          for i in start..<(start + 10) { buf.append(i) }
          try await source.write(buffer: &buf)
        }
        source.finish()
        try await group.next()
      }
    }
  }
}
#endif

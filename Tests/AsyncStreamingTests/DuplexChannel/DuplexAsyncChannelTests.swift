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
struct DuplexAsyncChannelTests {
  // MARK: - Round-trip

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func roundTripForwardDirection() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 10)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerB = readerB

      var buf = UniqueArray<Int>(minimumCapacity: 5)
      for v in [1, 2, 3, 4, 5] { buf.append(v) }
      try await writerA.write(buffer: &buf)

      try await readerB.read { buffer, _ in
        #expect(buffer.count == 5)
        var c = buffer.consumeAll()
        var collected: [Int] = []
        while let v = c.next() { collected.append(v) }
        #expect(collected == [1, 2, 3, 4, 5])
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func roundTripReverseDirection() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 10)
    ) { writerA, readerA, writerB, readerB in
      var readerA = readerA
      var writerB = writerB

      var buf = UniqueArray<Int>(minimumCapacity: 3)
      for v in [10, 20, 30] { buf.append(v) }
      try await writerB.write(buffer: &buf)

      try await readerA.read { buffer, _ in
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
  func directionsAreIndependent() async throws {
    // Bytes sent on the forward direction must NOT appear on the side that
    // sent them.
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerA = readerA
      var writerB = writerB
      var readerB = readerB

      var fwdBuf = UniqueArray<Int>(minimumCapacity: 1)
      fwdBuf.append(1)
      try await writerA.write(buffer: &fwdBuf)

      var revBuf = UniqueArray<Int>(minimumCapacity: 1)
      revBuf.append(99)
      try await writerB.write(buffer: &revBuf)

      // readerB sees the forward write.
      try await readerB.read { buffer, _ in
        #expect(buffer.count == 1)
        var c = buffer.consumeAll()
        #expect(c.next() == 1)
      }

      // readerA sees the reverse write, and only that.
      try await readerA.read { buffer, _ in
        #expect(buffer.count == 1)
        var c = buffer.consumeAll()
        #expect(c.next() == 99)
      }
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func concurrentReadsOnBothDirections() async throws {
    try await withThrowingTaskGroup(of: [Int].self) { group in
      try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
        of: Int.self,
        backpressureStrategy: .watermark(low: 5, high: 20)
      ) { writerA, readerA, writerB, readerB in
        var writerA = writerA
        var readerA = readerA
        var writerB = writerB
        var readerB = readerB

        group.addTask {
          var collected: [Int] = []
          var done = false
          while !done {
            try await readerA.read { buffer, finalElement in
              var c = buffer.consumeAll()
              while let v = c.next() { collected.append(v) }
              if finalElement != nil { done = true }
            }
          }
          return collected
        }

        // Forward: write 0..<10 from main scope.
        var fwd = UniqueArray<Int>(minimumCapacity: 10)
        for i in 0..<10 { fwd.append(i) }
        try await writerA.write(buffer: &fwd)
        writerA.finish()

        // Reverse: write 100..<110 from main scope.
        var rev = UniqueArray<Int>(minimumCapacity: 10)
        for i in 100..<110 { rev.append(i) }
        try await writerB.write(buffer: &rev)
        writerB.finish()

        // Drain forward from the main scope.
        var forwardCollected: [Int] = []
        var done = false
        while !done {
          try await readerB.read { buffer, finalElement in
            var c = buffer.consumeAll()
            while let v = c.next() { forwardCollected.append(v) }
            if finalElement != nil { done = true }
          }
        }
        #expect(forwardCollected == Array(0..<10))

        let reverseCollected = try await group.next() ?? []
        #expect(reverseCollected == Array(100..<110))
      }
    }
  }

  // MARK: - Half-close

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func finishingOneDirectionLeavesTheOtherOpen() async throws {
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerA = readerA
      var writerB = writerB
      var readerB = readerB

      // Close forward direction.
      var fwdBuf = UniqueArray<Int>(minimumCapacity: 1)
      fwdBuf.append(7)
      try await writerA.write(buffer: &fwdBuf)
      writerA.finish()

      // Reverse direction still works.
      var revBuf = UniqueArray<Int>(minimumCapacity: 1)
      revBuf.append(8)
      try await writerB.write(buffer: &revBuf)

      // Forward EOS is fused with the buffered element on the same read.
      var sawForwardFinal = false
      try await readerB.read { buffer, finalElement in
        #expect(buffer.count == 1)
        if finalElement != nil { sawForwardFinal = true }
        buffer.removeAll()
      }
      #expect(sawForwardFinal)

      // Reverse still delivers elements after forward is closed.
      try await readerA.read { buffer, finalElement in
        #expect(buffer.count == 1)
        #expect(finalElement == nil)
        buffer.removeAll()
      }
    }
  }

  // MARK: - Final element

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func finalElementDeliveredOnFinish() async throws {
    try await DuplexAsyncChannel<Int, String, Never>.withDuplex(
      of: Int.self,
      withFinalElement: String.self,
      backpressureStrategy: .watermark(low: 2, high: 8)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerB = readerB

      var buf = UniqueArray<Int>(minimumCapacity: 3)
      for v in [1, 2, 3] { buf.append(v) }
      try await writerA.write(buffer: &buf)
      writerA.finish(finalElement: "trailers")

      var collected: [Int] = []
      var trailerSeen: String? = nil
      var done = false
      while !done {
        try await readerB.read { buffer, finalElement in
          var c = buffer.consumeAll()
          while let v = c.next() { collected.append(v) }
          if let f = finalElement {
            trailerSeen = f
            done = true
          }
        }
      }
      #expect(collected == [1, 2, 3])
      #expect(trailerSeen == "trailers")
    }
  }

  // MARK: - Failure isolation

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func failureOnOneDirectionDoesNotPoisonTheOther() async throws {
    struct TestError: Error, Equatable {}

    try await DuplexAsyncChannel<Int, Void, TestError>.withDuplex(
      of: Int.self,
      throwing: TestError.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerA = readerA
      var writerB = writerB
      var readerB = readerB

      // Send a final element on reverse so we can verify it survives.
      var revBuf = UniqueArray<Int>(minimumCapacity: 1)
      revBuf.append(42)
      try await writerB.write(buffer: &revBuf)
      writerB.finish()

      // Fail forward direction.
      writerA.finish(throwing: TestError())

      // readerB sees the forward failure.
      do {
        try await readerB.read { _, _ in }
        Issue.record("expected throw on forward direction")
      } catch let EitherError<EitherError<TestError, CancellationError>, Never>.first(.first(err)) {
        #expect(err == TestError())
      } catch {
        Issue.record("unexpected error: \(error)")
      }

      // readerA still gets the reverse element + EOS unaffected. The EOS
      // is fused with the buffered element on the same read.
      var sawFinal = false
      try await readerA.read { buffer, finalElement in
        #expect(buffer.count == 1)
        var c = buffer.consumeAll()
        #expect(c.next() == 42)
        if finalElement != nil { sawFinal = true }
      }
      #expect(sawFinal)
    }
  }

  // MARK: - Backpressure isolation

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func backpressureOnOneDirectionDoesNotBlockTheOther() async throws {
    // Forward writer is suspended on backpressure (writes more than the
    // high watermark with no concurrent reader). Reverse must still
    // accept writes and deliver them while forward is stuck.
    try await withThrowingTaskGroup(of: Void.self) { group in
      try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
        of: Int.self,
        backpressureStrategy: .watermark(low: 1, high: 2)
      ) { writerA, readerA, writerB, readerB in
        var writerA = writerA
        var readerA = readerA
        var writerB = writerB
        var readerB = readerB

        // Forward writer: 4 elements with high=2 → suspends mid-batch.
        group.addTask {
          var fwd = UniqueArray<Int>(minimumCapacity: 4)
          for i in 0..<4 { fwd.append(i) }
          try await writerA.write(buffer: &fwd)
        }

        // Even with forward backpressured, reverse fully works.
        var rev = UniqueArray<Int>(minimumCapacity: 1)
        rev.append(99)
        try await writerB.write(buffer: &rev)
        try await readerA.read { buffer, _ in
          #expect(buffer.count == 1)
          var c = buffer.consumeAll()
          #expect(c.next() == 99)
        }

        // Drain forward (4 elements) so the suspended writer task can
        // complete and we can join it before exiting the scope.
        var collected: [Int] = []
        while collected.count < 4 {
          try await readerB.read { buffer, _ in
            var c = buffer.consumeAll()
            while let v = c.next() { collected.append(v) }
          }
        }
        #expect(collected == [0, 1, 2, 3])
        try await group.waitForAll()
      }
    }
  }

  // MARK: - Multi-producer per direction

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func clonedWriterCanProduceConcurrently() async throws {
    // Two writes happen sequentially through the original writer and its
    // clone, demonstrating both share the same direction. We can't issue
    // `finish()` from inside an escaping closure (it consumes the writer),
    // so we keep the multi-producer demonstration sequential here.
    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 50)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerB = readerB
      _ = readerA
      _ = writerB

      var clone = writerA.clone()

      var buf1 = UniqueArray<Int>(minimumCapacity: 5)
      for v in 0..<5 { buf1.append(v) }
      try await writerA.write(buffer: &buf1)

      var buf2 = UniqueArray<Int>(minimumCapacity: 5)
      for v in 100..<105 { buf2.append(v) }
      try await clone.write(buffer: &buf2)

      // Either writer can close the direction independently. The other
      // writer is still alive but the channel is now finishing.
      writerA.finish()
      clone.finish()

      nonisolated(unsafe) var collected = Set<Int>()
      var done = false
      while !done {
        try await readerB.read { buffer, finalElement in
          var c = buffer.consumeAll()
          while let v = c.next() { collected.insert(v) }
          if finalElement != nil { done = true }
        }
      }
      #expect(collected == Set([0, 1, 2, 3, 4, 100, 101, 102, 103, 104]))
    }
  }

  // MARK: - Body-error wrapping

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readBodyErrorsWrappedInSecond() async throws {
    struct BodyError: Error, Equatable {}

    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerB = readerB
      _ = readerA
      _ = writerB

      var buf = UniqueArray<Int>(minimumCapacity: 1)
      buf.append(1)
      try await writerA.write(buffer: &buf)

      do {
        try await readerB.read { _, _ throws(BodyError) in
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

  // MARK: - Scope cleanup

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func scopeFinalizesBothDirectionsOnReturn() async throws {
    nonisolated(unsafe) var aTerminated = false
    nonisolated(unsafe) var bTerminated = false
    await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 4)
    ) { writerA, readerA, writerB, readerB in
      writerA.setOnTerminationCallback { aTerminated = true }
      writerB.setOnTerminationCallback { bTerminated = true }
      _ = readerA
      _ = readerB
    }
    #expect(aTerminated)
    #expect(bTerminated)
  }

  // MARK: - Protocol conformance

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func writerConformsToCallerAsyncWriter() async throws {
    // Exercise CallerAsyncWriter.finish(buffer:finalElement:) by calling
    // it through a generic function that only sees the protocol.
    func finishViaProtocol<W: CallerAsyncWriter & ~Copyable>(
      _ writer: consuming W,
      finalElement: consuming W.FinalElement?
    ) async throws(W.WriteFailure) where W.WriteElement == Int {
      var buf = UniqueArray<Int>(minimumCapacity: 3)
      buf.append(7)
      buf.append(8)
      buf.append(9)
      try await writer.finish(buffer: &buf, finalElement: finalElement)
    }

    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 5, high: 50)
    ) { writerA, readerA, writerB, readerB in
      var readerB = readerB
      _ = readerA
      _ = writerB

      try await finishViaProtocol(writerA, finalElement: .some(()))

      var collected: [Int] = []
      var sawFinal = false
      var done = false
      while !done {
        try await readerB.read { buffer, finalElement in
          var c = buffer.consumeAll()
          while let v = c.next() { collected.append(v) }
          if finalElement != nil {
            sawFinal = true
            done = true
          }
        }
      }
      #expect(collected == [7, 8, 9])
      #expect(sawFinal)
    }
  }

  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  @Test
  func readerConformsToAsyncReader() async throws {
    // Exercise AsyncReader.read through a generic function that only
    // sees the protocol.
    func readOneChunk<R: AsyncReader & ~Copyable & ~Escapable>(
      _ reader: inout R
    ) async throws -> [Int] where R.ReadElement == Int, R.Buffer == UniqueDeque<Int> {
      nonisolated(unsafe) var collected: [Int] = []
      do throws(EitherError<R.ReadFailure, Never>) {
        try await reader.read { (buffer: inout R.Buffer, _: consuming R.FinalElement?) in
          var c = buffer.consumeAll()
          while let v = c.next() { collected.append(v) }
        }
      } catch {
        // Swallow read-side errors for the test.
      }
      return collected
    }

    try await DuplexAsyncChannel<Int, Void, Never>.withDuplex(
      of: Int.self,
      backpressureStrategy: .watermark(low: 2, high: 10)
    ) { writerA, readerA, writerB, readerB in
      var writerA = writerA
      var readerB = readerB
      _ = readerA
      _ = writerB

      var buf = UniqueArray<Int>(minimumCapacity: 3)
      for v in [11, 22, 33] { buf.append(v) }
      try await writerA.write(buffer: &buf)

      let collected = try await readOneChunk(&readerB)
      #expect(collected == [11, 22, 33])
    }
  }
}
#endif

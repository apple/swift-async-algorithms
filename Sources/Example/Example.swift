//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.1)
import AsyncAlgorithms

@available(macOS 15.0, *)
@main
struct Example {
  static func main() async throws {
    let durationUnboundedMPSC = await ContinuousClock().measure {
      await testMPSCChannel(count: 1_000_000, backpressureStrategy: .unbounded())
    }
    print("Unbounded MPSC:", durationUnboundedMPSC)
    let durationHighLowMPSC = await ContinuousClock().measure {
      await testMPSCChannel(count: 1_000_000, backpressureStrategy: .watermark(low: 100, high: 500))
    }
    print("HighLow MPSC:", durationHighLowMPSC)
    let durationAsyncStream = await ContinuousClock().measure {
      await testAsyncStream(count: 1_000_000)
    }
    print("AsyncStream:", durationAsyncStream)
  }

  static func testMPSCChannel(
    count: Int,
    backpressureStrategy: MultiProducerSingleConsumerAsyncChannel<Int, Never>.Source.BackpressureStrategy
  ) async {
    await withTaskGroup(of: Void.self) { group in
      let channelAndSource = MultiProducerSingleConsumerAsyncChannel.makeChannel(
        of: Int.self,
        backpressureStrategy: backpressureStrategy
      )
      var channel = channelAndSource.channel
      var source = Optional.some(consume channelAndSource.source)

      group.addTask {
        var source = source.take()!
        for i in 0..<count {
          try! await source.send(i)
        }
        source.finish()
      }

      var counter = 0
      while let element = await channel.next() {
        counter = element
      }
      print(counter)
    }
  }

  static func testAsyncStream(count: Int) async {
    await withTaskGroup(of: Void.self) { group in
      let (stream, continuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .unbounded)

      group.addTask {
        for i in 0..<count {
          continuation.yield(i)
        }
        continuation.finish()
      }

      var counter = 0
      for await element in stream {
        counter = element
      }
      print(counter)
    }
  }
}
#else
@main
struct Example {
  static func main() async throws {
    fatalError("Example only supports Swift 6.0 and above")
  }
}
#endif

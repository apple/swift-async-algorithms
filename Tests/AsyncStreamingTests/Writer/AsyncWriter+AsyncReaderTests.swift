//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if UnstableAsyncStreaming
#if !canImport(Darwin) || swift(>=6.3)  // Disabled on older compilers on Darwin due to a runtime crash
import _AsyncStreaming
import Testing

@Suite
struct AsyncWriterAsyncReaderTests {
  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeReaderToWriter() async {
    let reader = [1, 2, 3, 4, 5].asyncReader()
    var writer = TestWriter()

    try! await writer.write(reader)

    #expect(writer.storage == [1, 2, 3, 4, 5])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeEmptyReaderToWriter() async {
    let reader = [Int]().asyncReader()
    var writer = TestWriter()

    try! await writer.write(reader)

    #expect(writer.storage == [])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeLargeReaderToWriter() async {
    let data = Array(1...100)
    let reader = data.asyncReader()
    var writer = TestWriter()

    try! await writer.write(reader)

    #expect(writer.storage == data)
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeReaderStreamingBehavior() async {
    // Create a reader that will produce multiple spans
    struct ChunkedReader: AsyncReader {
      typealias ReadElement = Int
      typealias ReadFailure = Never

      var data: [Int]
      var position: Int = 0
      let chunkSize: Int

      mutating func read<Return, Failure: Error>(
        maximumCount: Int?,
        body: (consuming Span<Int>) async throws(Failure) -> Return
      ) async throws(EitherError<Never, Failure>) -> Return {
        do {
          guard position < data.count else {
            return try await body([Int]().span)
          }

          let count = min(chunkSize, data.count - position)
          let endIndex = position + count
          defer { position = endIndex }
          return try await body(data[position..<endIndex].span)
        } catch {
          throw .second(error)
        }
      }
    }

    let reader = ChunkedReader(data: [1, 2, 3, 4, 5, 6], position: 0, chunkSize: 2)
    var writer = TestWriter()

    try! await writer.write(reader)

    #expect(writer.storage == [1, 2, 3, 4, 5, 6])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeTransformedReaderToWriter() async {
    let reader = [1, 2, 3, 4, 5].asyncReader().map { $0 * 2 }
    var writer = TestWriter()

    try! await writer.write(reader)

    #expect(writer.storage == [2, 4, 6, 8, 10])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func writeMultipleReadersToSameWriter() async {
    let reader1 = [1, 2, 3].asyncReader()
    let reader2 = [4, 5, 6].asyncReader()
    var writer = TestWriter()

    try! await writer.write(reader1)
    try! await writer.write(reader2)

    #expect(writer.storage == [1, 2, 3, 4, 5, 6])
  }

  @Test
  @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
  func pipingDataBetweenReaderAndWriter() async {
    // This test simulates a typical use case: reading from one source
    // and writing to another destination
    let sourceData = [10, 20, 30, 40, 50]
    let reader = sourceData.asyncReader()
    var writer = TestWriter()

    // Pipe all data from reader to writer
    try! await writer.write(reader)

    #expect(writer.storage == sourceData)
  }
}
#endif
#endif

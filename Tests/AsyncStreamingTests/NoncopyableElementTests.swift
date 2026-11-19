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
import Testing

// These tests use a noncopyable element type with every reader, writer and
// adapter API that accepts one. They check that each API compiles for such an
// element, delivers the elements in order and frees every element.

// MARK: - Noncopyable element

/// Counts the live ``Token`` instances of one test, so the test can check that
/// every element was freed.
private final class TokenTracker {
  var created = 0
  var live = 0
}

private struct Token: ~Copyable {
  let value: Int
  let tracker: TokenTracker

  init(_ value: Int, tracker: TokenTracker) {
    self.value = value
    self.tracker = tracker
    tracker.created += 1
    tracker.live += 1
  }

  deinit {
    self.tracker.live -= 1
  }
}

/// Removes every token from `container` and returns their values in order.
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
private func drainValues<Container: RangeReplaceableContainer<Token> & ~Copyable>(
  _ container: inout Container
) -> [Int] where Container.Element: ~Copyable {
  var values: [Int] = []
  var consumer = container.consumeAll()
  while let token = consumer.next() {
    values.append(token.value)
  }
  return values
}

// MARK: - Readers

/// The chunks every reader below delivers. The final element arrives with the
/// last chunk, so piping goes through both `write` and `finish`.
private let defaultChunks: [[Int]] = [[1, 2], [3]]

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
private struct TokenAsyncReader: ~Copyable, AsyncReader {
  typealias ReadElement = Token
  typealias Buffer = UniqueArray<Token>
  typealias ReadFailure = Never
  typealias FinalElement = Void

  let tracker: TokenTracker
  let chunks: [[Int]]
  var nextChunk = 0

  init(tracker: TokenTracker, chunks: [[Int]] = defaultChunks) {
    self.tracker = tracker
    self.chunks = chunks
  }

  mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout UniqueArray<Token>, Void?) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    precondition(self.nextChunk < self.chunks.count, "read called after end-of-stream")
    var buffer = UniqueArray<Token>()
    for value in self.chunks[self.nextChunk] {
      buffer.append(Token(value, tracker: self.tracker))
    }
    self.nextChunk += 1
    let isLast = self.nextChunk == self.chunks.count
    do {
      return try await body(&buffer, isLast ? () : nil)
    } catch {
      throw .second(error)
    }
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
private struct TokenCallerAsyncReader: ~Copyable, CallerAsyncReader {
  typealias ReadElement = Token
  typealias ReadFailure = Never
  typealias FinalElement = Void

  let tracker: TokenTracker
  let chunks: [[Int]]
  var nextChunk = 0

  init(tracker: TokenTracker, chunks: [[Int]] = defaultChunks) {
    self.tracker = tracker
    self.chunks = chunks
  }

  mutating func read<Buffer: RangeReplaceableContainer<Token> & ~Copyable>(
    into buffer: inout Buffer
  ) async throws(Never) -> Void? where Buffer.Element: ~Copyable {
    precondition(self.nextChunk < self.chunks.count, "read called after end-of-stream")
    for value in self.chunks[self.nextChunk] {
      buffer.append(Token(value, tracker: self.tracker))
    }
    self.nextChunk += 1
    return self.nextChunk == self.chunks.count ? () : nil
  }
}

// MARK: - Writers

/// What a writer received. Writers are consumed by `pipe` and `finish`, so the
/// tests read the results from here.
private final class WriteRecord {
  var values: [Int] = []
  var finished = false
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
private struct TokenCallerAsyncWriter: ~Copyable, CallerAsyncWriter {
  typealias WriteElement = Token
  typealias WriteFailure = Never
  typealias FinalElement = Void

  let record: WriteRecord

  mutating func write<Buffer: RangeReplaceableContainer<Token> & ~Copyable>(
    buffer: inout Buffer
  ) async throws(Never) where Buffer.Element: ~Copyable {
    self.record.values += drainValues(&buffer)
  }

  consuming func finish<Buffer: RangeReplaceableContainer<Token> & ~Copyable>(
    buffer: inout Buffer,
    finalElement: consuming Void
  ) async throws(Never) where Buffer.Element: ~Copyable {
    self.record.values += drainValues(&buffer)
    self.record.finished = true
  }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
private struct TokenAsyncWriter: ~Copyable, AsyncWriter {
  typealias WriteElement = Token
  typealias Buffer = UniqueArray<Token>
  typealias WriteFailure = Never
  typealias FinalElement = Void

  let record: WriteRecord

  mutating func write<Return: ~Copyable, Failure: Error>(
    _ body: (inout UniqueArray<Token>) async throws(Failure) -> Return
  ) async throws(EitherError<Never, Failure>) -> Return {
    var buffer = UniqueArray<Token>(minimumCapacity: 2)
    let result: Return
    do {
      result = try await body(&buffer)
    } catch {
      throw .second(error)
    }
    self.record.values += drainValues(&buffer)
    return result
  }

  consuming func finish(finalElement: consuming Void) async throws(Never) {
    self.record.finished = true
  }
}

private struct StopError: Error, Equatable {}

// MARK: - Tests

@Suite
struct NoncopyableElementCollectTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectInto() async throws {
    let tracker = TokenTracker()
    do {
      var target = RigidArray<Token>(capacity: 3)
      try await TokenAsyncReader(tracker: tracker).collect(into: &target)
      #expect(drainValues(&target) == [1, 2, 3])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectExactlyInto() async throws {
    let tracker = TokenTracker()
    do {
      var target = RigidArray<Token>(capacity: 3)
      try await TokenAsyncReader(tracker: tracker).collect(exactlyInto: &target)
      #expect(drainValues(&target) == [1, 2, 3])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectExactlyIntoThrowsOnLeftOverElementsAndFreesThem() async throws {
    let tracker = TokenTracker()
    do {
      var target = RigidArray<Token>(capacity: 2)
      do {
        try await TokenAsyncReader(tracker: tracker).collect(exactlyInto: &target)
        Issue.record("Expected error")
      } catch {
        let expected = EitherError<
          Never, EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>
        >.second(.first(AsyncReaderLeftOverElementsError()))
        #expect(error == expected)
      }
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectExactlyIntoThrowsOnInsufficientElementsAndFreesThem() async throws {
    let tracker = TokenTracker()
    do {
      var target = RigidArray<Token>(capacity: 4)
      do {
        try await TokenAsyncReader(tracker: tracker).collect(exactlyInto: &target)
        Issue.record("Expected error")
      } catch {
        let expected = EitherError<
          Never, EitherError<AsyncReaderLeftOverElementsError, AsyncReaderInsufficientElementsError>
        >.second(.second(AsyncReaderInsufficientElementsError()))
        #expect(error == expected)
      }
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test(arguments: [3, 5])
  func collectIntoMaximumSize(maximumSize: Int) async throws {
    let tracker = TokenTracker()
    do {
      var target = UniqueArray<Token>()
      try await TokenAsyncReader(tracker: tracker).collect(into: &target, maximumSize: maximumSize)
      #expect(drainValues(&target) == [1, 2, 3])
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func collectIntoMaximumSizeThrowsOnLeftOverElementsAndFreesThem() async throws {
    let tracker = TokenTracker()
    do {
      var target = UniqueArray<Token>()
      do {
        try await TokenAsyncReader(tracker: tracker).collect(into: &target, maximumSize: 2)
        Issue.record("Expected error")
      } catch {
        let expected = EitherError<Never, AsyncReaderLeftOverElementsError>.second(AsyncReaderLeftOverElementsError())
        #expect(error == expected)
      }
    }
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}

@Suite
struct NoncopyableElementForEachBufferTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func forEachBuffer() async throws {
    let tracker = TokenTracker()
    var values: [Int] = []

    await TokenAsyncReader(tracker: tracker).forEachBuffer { (buffer: inout UniqueArray<Token>) async -> Void in
      values += drainValues(&buffer)
    }

    #expect(values == [1, 2, 3])
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func throwingForEachBufferFreesElementsWhenBodyThrows() async throws {
    let tracker = TokenTracker()
    var values: [Int] = []

    do {
      _ = try await TokenAsyncReader(tracker: tracker).forEachBuffer {
        (buffer: inout UniqueArray<Token>) async throws(StopError) -> Void in
        values += drainValues(&buffer)
        throw StopError()
      }
      Issue.record("Expected error")
    } catch {
      #expect(error == .second(StopError()))
    }

    #expect(values == [1, 2])
    #expect(tracker.created == 2)
    #expect(tracker.live == 0)
  }
}

@Suite
struct NoncopyableElementPipeTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asyncReaderPipeIntoCallerAsyncWriter() async throws {
    let tracker = TokenTracker()
    let record = WriteRecord()

    try await TokenAsyncReader(tracker: tracker).pipe(into: TokenCallerAsyncWriter(record: record))

    #expect(record.values == [1, 2, 3])
    #expect(record.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asyncReaderPipeCopyingIntoAsyncWriter() async throws {
    let tracker = TokenTracker()
    let record = WriteRecord()

    try await TokenAsyncReader(tracker: tracker).pipe(copyingInto: TokenAsyncWriter(record: record))

    #expect(record.values == [1, 2, 3])
    #expect(record.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func callerAsyncReaderPipeIntoAsyncWriter() async throws {
    let tracker = TokenTracker()
    let record = WriteRecord()

    try await TokenCallerAsyncReader(tracker: tracker).pipe(into: TokenAsyncWriter(record: record))

    #expect(record.values == [1, 2, 3])
    #expect(record.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func callerAsyncReaderPipeBufferingIntoCallerAsyncWriter() async throws {
    let tracker = TokenTracker()
    let record = WriteRecord()

    try await TokenCallerAsyncReader(tracker: tracker).pipe(
      bufferingInto: TokenCallerAsyncWriter(record: record),
      intermediateCapacity: 2
    )

    #expect(record.values == [1, 2, 3])
    #expect(record.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}

@Suite
struct NoncopyableElementAdapterTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asCallerAsyncWriter() async throws {
    let tracker = TokenTracker()
    let record = WriteRecord()

    let writer: AsyncWriterCallerAsyncWriterAdapter<TokenAsyncWriter> =
      TokenAsyncWriter(record: record).asCallerAsyncWriter()
    try await TokenAsyncReader(tracker: tracker).pipe(into: writer)

    #expect(record.values == [1, 2, 3])
    #expect(record.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asAsyncWriter() async throws {
    let tracker = TokenTracker()
    let record = WriteRecord()

    let writer: CallerAsyncWriterAsyncWriterAdapter<TokenCallerAsyncWriter, UniqueArray<Token>> =
      TokenCallerAsyncWriter(record: record).asAsyncWriter(initialCapacity: 2)
    try await TokenAsyncReader(tracker: tracker).pipe(copyingInto: writer)

    #expect(record.values == [1, 2, 3])
    #expect(record.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asAsyncWriterBufferOf() async throws {
    let tracker = TokenTracker()
    let record = WriteRecord()

    let writer = TokenCallerAsyncWriter(record: record).asAsyncWriter(
      bufferOf: UniqueArray<Token>.self,
      initialCapacity: 2
    )
    try await TokenCallerAsyncReader(tracker: tracker).pipe(into: writer)

    #expect(record.values == [1, 2, 3])
    #expect(record.finished)
    #expect(tracker.created == 3)
    #expect(tracker.live == 0)
  }
}

@Suite
struct NoncopyableElementFinishTests {
  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func asyncWriterFinish() async throws {
    let record = WriteRecord()

    await TokenAsyncWriter(record: record).finish()

    #expect(record.finished)
  }

  @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @Test
  func callerAsyncWriterFinish() async throws {
    let record = WriteRecord()

    await TokenCallerAsyncWriter(record: record).finish()

    #expect(record.values.isEmpty)
    #expect(record.finished)
  }
}

#endif
